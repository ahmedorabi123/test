require "digest"

module Sales
  # Sales::ManualRefundCreator
  #
  # Creates a manual (non-Shopify) refund against an existing Order, optionally
  # restocks inventory, and posts the partial-refund journal entry.
  #
  # Input shape:
  #   {
  #     order_id:  <uuid>,
  #     amount:    "12.50",            # required, > 0, ≤ remaining refundable
  #     currency:  "USD",              # optional, defaults to order.currency
  #     reason:    "customer_change",  # optional
  #     note:      "...",              # optional
  #     restock:   true,               # if true, restock line-items below
  #     restock_warehouse_id: <uuid>,  # required when restock=true
  #     line_items: [                  # optional but recommended; used for restock + JE accuracy
  #       { order_line_item_id:, quantity:, subtotal: }
  #     ]
  #   }
  class ManualRefundCreator
    class InvalidInput < StandardError; end

    def self.call(attrs)
      new(attrs).call
    end

    def initialize(attrs)
      @attrs = attrs.to_h.with_indifferent_access
    end

    def call
      validate!
      order = Order.find(@attrs[:order_id])
      amount = @attrs[:amount].to_d
      raise InvalidInput, "amount must be > 0" if amount <= 0

      idempotency_key = @attrs[:idempotency_key].presence
      content_hash = build_content_hash(order, amount)
      if (existing = find_existing_refund(order, idempotency_key, content_hash))
        return existing
      end

      already_refunded = order.refunds.sum(:amount).to_d
      remaining = order.total_price.to_d - already_refunded
      raise InvalidInput, "amount exceeds remaining refundable (#{remaining})" if amount > remaining

      Refund.transaction do
        status = @attrs[:status].presence_in(::Refund::STATUSES) || "processed"
        kind = @attrs[:kind].presence_in(::Refund::KINDS) || inferred_kind
        refund = Refund.create!(
          order:        order,
          amount:       amount,
          currency:     (@attrs[:currency].presence || order.currency).upcase,
          reason:       @attrs[:reason],
          note:         @attrs[:note],
          status:       status,
          kind:         kind,
          idempotency_key: idempotency_key,
          content_hash: content_hash,
          restock:      restock?,
          processed_at: Time.current
        )
        build_line_items(refund)
        if refund.processed?
          restock!(refund) if restock?
          post_journal(refund)
          flag_order_status(order)
          recompute_customer_stats(order)
        end
        refund
      end
    end

    private

    def validate!
      raise InvalidInput, "order_id required" if @attrs[:order_id].blank?
      raise InvalidInput, "amount required"   if @attrs[:amount].blank?
      if restock? && @attrs[:restock_warehouse_id].blank?
        raise InvalidInput, "restock_warehouse_id required when restock=true"
      end
    end

    def restock?
      @attrs[:restock].to_s == "true" || @attrs[:restock] == true
    end

    def inferred_kind
      @attrs[:reason].to_s.downcase == "estebdal" ? "estebdal" : "manual"
    end

    def find_existing_refund(order, idempotency_key, content_hash)
      return Refund.find_by(idempotency_key: idempotency_key) if idempotency_key.present?

      Refund.where(order: order, shopify_refund_id: nil, content_hash: content_hash)
            .where("created_at >= ?", 5.minutes.ago)
            .order(:created_at)
            .first
    end

    def build_content_hash(order, amount)
      normalized_lines = Array(@attrs[:line_items]).map do |li|
        h = li.to_h.with_indifferent_access
        [h[:order_line_item_id].to_s, h[:quantity].to_i, h[:subtotal].to_s.to_d.round(2).to_s].join(":")
      end.sort.join("|")
      Digest::SHA256.hexdigest([
        order.id,
        amount.round(2).to_s,
        @attrs[:reason].to_s,
        restock?,
        @attrs[:restock_warehouse_id].to_s,
        normalized_lines
      ].join("|"))
    end

    def build_line_items(refund)
      Array(@attrs[:line_items]).each do |li|
        h = li.to_h.with_indifferent_access
        oli = refund.order.line_items.find(h[:order_line_item_id])
        qty = h[:quantity].to_i
        next if qty <= 0
        subtotal = h[:subtotal].present? ? h[:subtotal].to_d : (oli.price.to_d * qty)
        refund.refund_line_items.create!(
          order_line_item: oli,
          quantity:        qty,
          subtotal:        subtotal
        )
      end
    end

    def restock!(refund)
      warehouse = Warehouse.find(@attrs[:restock_warehouse_id])
      refund.refund_line_items.each do |rli|
        oli = rli.order_line_item
        next unless oli&.variant_id

        si = StockItem.find_or_create_by!(variant_id: oli.variant_id, warehouse_id: warehouse.id) do |s|
          s.quantity_on_hand = 0
        end
        Inventory::WriteMovement.call(
          stock_item: si,
          delta:      rli.quantity,
          reason:     "refund_restock",
          reference:  refund
        )
      end
      refund.update!(inventory_restocked: true)
    end

    def post_journal(refund)
      ::Accounting::PartialRefundJournalHandler.call(refund)
    rescue StandardError => e
      Rails.logger.warn "[ManualRefundCreator] journal failure for refund=#{refund.id}: #{e.message}"
    end

    def flag_order_status(order)
      total_refunded = order.refunds.sum(:amount).to_d
      if total_refunded >= order.total_price.to_d
        order.update!(financial_status: "refunded", total_refunded: total_refunded)
      elsif total_refunded > 0
        order.update!(financial_status: "partially_refunded", total_refunded: total_refunded)
      end
    end

    def recompute_customer_stats(order)
      return unless order.customer

      ::Crm::CustomerStatsRecomputer.call(order.customer)
    rescue StandardError => e
      Rails.logger.warn "[ManualRefundCreator] customer stats failure for order=#{order.id}: #{e.message}"
    end
  end
end
