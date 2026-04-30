module Sales
  # Drives explicit, validated transitions on an Order.
  #
  # Two parallel state axes mirror Shopify:
  #   - status:           pending → processing → fulfilled
  #                       any     → cancelled
  #   - financial_status: pending → authorized → paid → refunded
  #                                                   → partially_paid
  #
  # Side effects per transition:
  #   - to "paid":      posts the sale journal (idempotent)
  #   - to "fulfilled": deducts stock for each line item via Inventory::WriteMovement
  #   - to "cancelled" (after paid): reverses the sale journal
  #
  # Returns the order; raises InvalidTransition on illegal moves.
  class OrderStateMachine
    class InvalidTransition < StandardError; end

    LEGAL_STATUS = {
      "pending"    => %w[processing fulfilled cancelled],
      "processing" => %w[fulfilled cancelled],
      "fulfilled"  => %w[cancelled],
      "cancelled"  => [],
      "refunded"   => []
    }.freeze

    LEGAL_FINANCIAL = {
      "pending"        => %w[authorized paid voided],
      "authorized"     => %w[paid voided],
      "paid"           => %w[partially_paid refunded],
      "partially_paid" => %w[paid refunded],
      "refunded"       => [],
      "voided"         => []
    }.freeze

    def self.call(order, to:, actor: nil)
      new(order, to: to, actor: actor).call
    end

    def initialize(order, to:, actor:)
      @order = order
      @to    = to.to_s
      @actor = actor
    end

    def call
      kind = classify(@to)
      case kind
      when :status    then transition_status!
      when :financial then transition_financial!
      else
        raise InvalidTransition, "Unknown target state '#{@to}'"
      end
      @order.reload
    end

    private

    def classify(target)
      return :status    if LEGAL_STATUS.keys.include?(target)
      return :financial if LEGAL_FINANCIAL.keys.include?(target)
      nil
    end

    def transition_status!
      from = @order.status.to_s
      legal = LEGAL_STATUS.fetch(from, [])
      unless legal.include?(@to)
        raise InvalidTransition, "Cannot move order #{@order.order_number} from status=#{from} to #{@to}"
      end

      Order.transaction do
        @order.update!(status: @to, cancelled_at: (Time.current if @to == "cancelled"))
        on_status_change(from, @to)
      end
    end

    def transition_financial!
      from = @order.financial_status.to_s
      legal = LEGAL_FINANCIAL.fetch(from, [])
      unless legal.include?(@to)
        raise InvalidTransition,
              "Cannot move order #{@order.order_number} from financial_status=#{from} to #{@to}"
      end

      Order.transaction do
        @order.update!(financial_status: @to)
        on_financial_change(from, @to)
      end
    end

    def on_status_change(from, to)
      case to
      when "fulfilled"
        deduct_inventory!
        safe { post_cogs_for_order! }
      when "cancelled"
        # If the order was already paid, reverse the journal entry.
        if %w[paid partially_paid].include?(@order.financial_status.to_s)
          safe { ::Accounting::RefundReversalHandler.call(@order) }
        end
      end
      log_transition!(field: "status", from: from, to: to)
    end

    def on_financial_change(from, to)
      if to == "paid"
        safe { ::Accounting::PostSaleJournalHandler.call(@order) }
      elsif to == "refunded"
        safe { ::Accounting::RefundReversalHandler.call(@order) }
      end
      log_transition!(field: "financial_status", from: from, to: to)
    end

    def deduct_inventory!
      warehouse = ::Inventory::WarehouseResolver.for_shopify_location(@order.location_id) ||
                  ::Inventory::WarehouseResolver.primary
      return unless warehouse

      @order.line_items.includes(:variant).each do |li|
        next unless li.variant_id
        si = StockItem.find_by(variant_id: li.variant_id, warehouse_id: warehouse.id)
        next unless si
        ::Inventory::WriteMovement.call(
          stock_item: si,
          delta:      -li.quantity,
          reason:     "fulfilled",
          reference:  @order
        )
      end
    end

    def safe
      yield
    rescue StandardError => e
      Rails.logger.error("[OrderStateMachine] side-effect failure: #{e.class}: #{e.message}")
    end

    # Manual-order COGS posting (for orders fulfilled directly, without a Shopify
    # Fulfillment record). Computes total cost from line_items.variant.cost_per_item.
    def post_cogs_for_order!
      idem_key = "cogs-order-#{@order.id}"
      return if JournalEntry.exists?(idempotency_key: idem_key)

      total = @order.line_items.includes(:variant).sum do |li|
        cost = li.variant&.cost_per_item.to_d
        cost * li.quantity.to_i
      end
      return if total <= 0

      JournalEntry.post!(
        {
          entry_date:      Date.current,
          description:     "COGS – #{@order.order_number}",
          currency:        @order.currency.presence || "USD",
          source_type:     "order",
          source_id:       @order.id,
          entry_type:      "sale",
          idempotency_key: idem_key
        },
        [
          { account_code: "5000", side: "debit",  amount: total,
            description: "COGS – #{@order.order_number}" },
          { account_code: "1200", side: "credit", amount: total,
            description: "Inventory consumed – #{@order.order_number}" }
        ]
      )
    end

    def log_transition!(field:, from:, to:)
      AuditLog.record(
        user:    @actor,
        action:  "order.#{field}_changed",
        subject: @order,
        diff:    { field => { from: from, to: to } }
      )
    rescue StandardError
      nil
    end
  end
end
