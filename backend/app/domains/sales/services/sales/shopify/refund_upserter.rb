module Sales
  module Shopify
    # Upserts a Shopify refunds/create webhook payload into a Refund row +
    # refund_line_items, then:
    #  - if restock requested, writes positive stock movements
    #  - posts/reverses the appropriate accounting journal entry:
    #      * full refund (amount >= order.total_price) → RefundReversalHandler
    #      * partial refund                           → PartialRefundJournalHandler
    #
    # Payload shape (Shopify refunds/create):
    #   {
    #     "id" => 111, "order_id" => 98765, "note" => "bad fit",
    #     "created_at" => "...", "processed_at" => "...",
    #     "transactions" => [ { "amount" => "50.00", "kind" => "refund" } ],
    #     "refund_line_items" => [
    #       { "id" => 22, "line_item_id" => 333, "quantity" => 1,
    #         "subtotal" => "24.99", "restock_type" => "return",
    #         "location_id" => 111 }
    #     ]
    #   }
    class RefundUpserter
      def self.call(payload)
        new(payload).call
      end

      def initialize(payload)
        @payload = payload.with_indifferent_access
      end

      def call
        ::Shopify::Origin.without_read_only do
          order = find_order
          return nil unless order

          shopify_refund_id = @payload[:id].to_i
          amount            = extract_amount
          currency          = (@payload[:currency].presence || order.currency || "EGP").upcase
          restock_requested = Array(@payload[:refund_line_items]).any? do |rli|
            rt = (rli[:restock_type] || rli["restock_type"]).to_s
            rt == "return"
          end

          refund = ActiveRecord::Base.transaction do
            refund = ::Refund.find_or_initialize_by(shopify_refund_id: shopify_refund_id)
            was_new = refund.new_record?

            refund.assign_attributes(
              order:              order,
              amount:             amount,
              currency:           currency,
              reason:             @payload[:reason].presence,
              note:               @payload[:note].presence,
              status:             "processed",
              kind:               exchange_order?(order) ? "exchange" : "shopify",
              restock:            restock_requested,
              transactions:       Array(@payload[:transactions]).map { |t| t.is_a?(Hash) ? t.to_h : {} },
              processed_at:       parse_time(@payload[:processed_at] || @payload[:created_at]) || Time.current,
              shopify_updated_at: parse_time(@payload[:updated_at])
            )
            refund.save!
            sync_line_items(refund)
            [refund, was_new]
          end.first

          # Outside the refund transaction: inventory + accounting (each idempotent).
          restock_inventory(refund)
          release_cancelled_reservations(refund)
          update_order_financial_state(refund)
          post_accounting(refund)

          refund
        end
      end

      private

      def find_order
        order_id = @payload[:order_id].to_i
        return nil if order_id.zero?
        ::Order.find_by(shopify_order_id: order_id)
      end

      def extract_amount
        txs = Array(@payload[:transactions])
        if txs.any?
          txs.select { |t| (t[:kind] || t["kind"]) == "refund" && (t[:status] || t["status"]).to_s != "failure" }
             .sum { |t| (t[:amount] || t["amount"]).to_s.to_d }
        else
          (@payload[:amount] || 0).to_s.to_d
        end
      rescue ArgumentError
        0.to_d
      end

      def sync_line_items(refund)
        incoming = Array(@payload[:refund_line_items])
        keep_ids = []
        incoming.each do |rli|
          rh = rli.with_indifferent_access
          line_item_shopify_id = rh[:line_item_id].to_i
          oli = refund.order.line_items.find_by(shopify_line_item_id: line_item_shopify_id)

          row = refund.refund_line_items.find_or_initialize_by(shopify_line_item_id: line_item_shopify_id)
          rt  = rh[:restock_type].to_s.presence_in(::RefundLineItem::RESTOCK_TYPES) || "no_restock"
          row.assign_attributes(
            order_line_item: oli,
            quantity:        rh[:quantity].to_i,
            subtotal:        (rh[:subtotal] || 0).to_s.to_d,
            restock:         rt == "return",
            restock_type:    rt,
            location_id:     rh[:location_id].presence&.to_i
          )
          row.save!
          keep_ids << row.id
        end
        refund.refund_line_items.where.not(id: keep_ids).destroy_all if incoming.any?
      end

      def restock_inventory(refund)
        return if refund.inventory_restocked?
        return unless refund.restock?

        fallback_wh = ::Inventory::WarehouseResolver.primary
        performed = false

        refund.refund_line_items.each do |rli|
          next unless rli.restock?
          next if rli.quantity.to_i <= 0
          variant = rli.order_line_item&.variant
          next unless variant

          wh = ::Inventory::WarehouseResolver.for_shopify_location(rli.location_id, fallback: fallback_wh) ||
               fallback_wh
          next unless wh

          stock_item = ::StockItem.find_or_create_by!(variant: variant, warehouse: wh) do |si|
            si.quantity_on_hand = 0
          end

          ::Inventory::WriteMovement.call(
            stock_item: stock_item,
            delta:      rli.quantity,
            reason:     "refund_restock",
            reference:  rli
          )
          ::Inventory::RestoreCostLayers.call(refund_line_item: rli, stock_item: stock_item)
          performed = true
        end

        refund.update!(inventory_restocked: true) if performed
      end

      def release_cancelled_reservations(refund)
        refund.refund_line_items.where(restock_type: "cancel").each do |rli|
          next unless rli.order_line_item

          ::Inventory::ReleaseLineReservation.call(rli.order_line_item, quantity: rli.quantity)
        end
      end

      def update_order_financial_state(refund)
        order = refund.order
        total_refunded = order.refunds.where(status: "processed").sum(:amount).to_d

        new_state =
          if total_refunded >= order.total_price.to_d
            "refunded"
          elsif total_refunded > 0 && %w[paid partially_refunded].include?(order.financial_status.to_s)
            "partially_refunded"
          else
            order.financial_status
          end

        return unless ::Order::FINANCIAL_STATUSES.include?(new_state)
        return if new_state == order.financial_status && order.total_refunded.to_d == total_refunded

        attrs = { financial_status: new_state, total_refunded: total_refunded }
        attrs[:status] = "refunded" if new_state == "refunded"
        order.update!(attrs)
      end

      # Posts accounting for each individual Shopify refund event.
      #
      # We ALWAYS use PartialRefundJournalHandler (idempotent per refund.id)
      # regardless of whether this is the refund that tips the order to fully
      # refunded. This avoids double-counting when a full refund follows one or
      # more prior partial refund journal entries.
      #
      # RefundReversalHandler is reserved for order CANCELLATION (OrderStateMachine).
      # COGS reversal is disabled until variant cost tracking is implemented.
      def post_accounting(refund)
        ::Accounting::PartialRefundJournalHandler.call(refund)
      rescue => e
        Rails.logger.error("[RefundUpserter] Accounting error for refund #{refund.id}: #{e.message}")
      end

      def exchange_order?(order)
        Array(order.tags).any? { |tag| tag.to_s.start_with?("estebdal_exchange_of:") }
      end

      def parse_time(v)
        return nil if v.blank?
        v.is_a?(Time) || v.is_a?(ActiveSupport::TimeWithZone) ? v : Time.zone.parse(v.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
