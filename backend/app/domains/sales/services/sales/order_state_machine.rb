module Sales
  # Drives explicit, validated transitions on an Order.
  #
  # Two parallel state axes mirror Shopify:
  #   - status:           pending → processing → fulfilled
  #                       any     → cancelled
  #   - financial_status: pending → authorized → paid
  #
  # Side effects per transition:
  #   - to "paid":      posts the sale journal (idempotent)
  #   - to "fulfilled": consumes fulfillment line items via Inventory::ConsumeReservation
  #   - to "cancelled" (after paid): reverses the sale journal via force: true
  #   - to "voided":    releases active reservations
  class OrderStateMachine
    class InvalidTransition < StandardError; end

    # NOTE: Once goods have shipped, an order can no longer be cancelled —
    # it must be returned/refunded. This is enforced by removing "cancelled"
    # from `fulfilled`'s legal next states.
    LEGAL_STATUS = {
      "pending"    => %w[processing fulfilled cancelled],
      "processing" => %w[fulfilled cancelled],
      "fulfilled"  => [],
      "cancelled"  => [],
      "refunded"   => []
    }.freeze

    LEGAL_FINANCIAL = {
      "pending"            => %w[authorized paid voided],
      "authorized"         => %w[paid voided],
      "paid"               => [],
      "partially_refunded" => [],
      "refunded"           => [],
      "voided"             => []
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
        safe { ensure_fulfillment_inventory_consumed! }
      when "cancelled"
        safe { ::Inventory::ReleaseOrderReservations.call(@order) }
        if %w[paid partially_refunded].include?(@order.financial_status.to_s)
          safe { ::Accounting::RefundReversalHandler.call(@order, force: true) }
        end
        safe { recompute_customer_stats }
      end
      log_transition!(field: "status", from: from, to: to)
    end

    def on_financial_change(from, to)
      case to
      when "paid"
        safe { ::Accounting::PostSaleJournalHandler.call(@order) }
        safe { recompute_customer_stats }
      when "voided"
        safe { ::Inventory::ReleaseOrderReservations.call(@order) }
        safe { recompute_customer_stats }
      end
      log_transition!(field: "financial_status", from: from, to: to)
    end

    def ensure_fulfillment_inventory_consumed!
      fulfillments = @order.fulfillments.successful.includes(:fulfillment_line_items)

      if fulfillments.empty?
        line_items = @order.line_items.map do |line_item|
          remaining = [line_item.quantity.to_i - line_item.fulfilled_quantity.to_i, 0].max
          next if remaining <= 0
          { order_line_item_id: line_item.id, quantity: remaining }
        end.compact

        fulfillment = ::Shipping::CreateManualFulfillment.call(
          order: @order,
          tracking_company: "Manual",
          line_items: line_items,
          transition_order: false,
          actor: @actor
        )
        fulfillments = [fulfillment]
      end

      fulfillments.each do |fulfillment|
        fulfillment.fulfillment_line_items.each do |fulfillment_line_item|
          ::Inventory::ConsumeReservation.call(fulfillment_line_item)
        end
        # COGS disabled: cost-per-product tracking not yet implemented.
        # Re-enable PostCogsHandler here when variant costs are reliable.
      end
    end

    def recompute_customer_stats
      return unless @order.customer_id
      ::Crm::CustomerStatsRecomputer.call(@order.customer)
    rescue StandardError => e
      Rails.logger.warn "[OrderStateMachine] customer stats failure: #{e.message}"
    end

    def safe
      yield
    rescue StandardError => e
      Rails.logger.error("[OrderStateMachine] side-effect failure: #{e.class}: #{e.message}")
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
