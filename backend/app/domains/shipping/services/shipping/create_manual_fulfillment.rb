module Shipping
  # Creates a manual Fulfillment record (no Shopify) for an order.
  # Consumes reservation/on-hand inventory for each fulfillment line. Optionally
  # transitions the order, which is idempotent for already-consumed lines.
  #
  # Inputs:
  #   order:           Order
  #   tracking_company:String  (e.g. "Bosta", "Aramex", "Manual")
  #   tracking_number: String
  #   tracking_url:    String (optional)
  #   service:         String (optional carrier service)
  #   shipped_at:      Time   (optional, defaults to now)
  #   line_items:      [{ order_line_item_id:, quantity: }, ...]
  #                    If empty, a fulfillment with no line items is still created.
  #   transition_order: Boolean (default true) — call OrderStateMachine to fulfilled
  #   actor:           User (for audit trail in state machine)
  class CreateManualFulfillment
    class InvalidInput < StandardError; end
    class AlreadyFulfilled < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(order:, tracking_company:, tracking_number: nil, tracking_url: nil,
                   service: nil, shipped_at: nil, line_items: [], transition_order: true, actor: nil)
      @order            = order
      @tracking_company = tracking_company.to_s.strip
      @tracking_number  = tracking_number.to_s.strip.presence
      @tracking_url     = tracking_url.to_s.strip.presence
      @service          = service.to_s.strip.presence
      @shipped_at       = shipped_at || Time.current
      @line_items       = Array(line_items)
      @transition_order = transition_order
      @actor            = actor
    end

    def call
      raise InvalidInput, "order is required"            unless @order
      raise InvalidInput, "tracking_company is required" if @tracking_company.blank?
      ensure_order_shippable!

      rows = normalized_rows
      ensure_not_over_fulfilled!(rows)

      fulfillment = nil
      ApplicationRecord.transaction do
        fulfillment = Fulfillment.create!(
          order:            @order,
          status:           "success",
          delivery_status:  "pending",
          tracking_company: @tracking_company,
          tracking_number:  @tracking_number,
          tracking_url:     @tracking_url,
          service:          @service,
          shipped_at:       @shipped_at
        )

        rows.each do |row|
          fulfillment.fulfillment_line_items.create!(
            order_line_item_id: row[:order_line_item_id],
            quantity:           row[:quantity]
          )
        end
      end

      fulfillment.fulfillment_line_items.each do |fulfillment_line_item|
        ::Inventory::ConsumeReservation.call(
          fulfillment_line_item,
          update_order_status: @transition_order
        )
      end
      ::Accounting::PostCogsHandler.call(fulfillment)
      ::Shipping::RecordShipmentEvent.call(
        fulfillment,
        kind: "created",
        payload: { status: fulfillment.status, tracking_company: fulfillment.tracking_company },
        actor: @actor,
        dedupe_key: "manual-fulfillment:#{fulfillment.id}:created"
      )

      if @transition_order && @order.status != "fulfilled" && should_transition_order?
        begin
          ::Sales::OrderStateMachine.call(@order.reload, to: "fulfilled", actor: @actor)
        rescue ::Sales::OrderStateMachine::InvalidTransition => e
          Rails.logger.warn("[CreateManualFulfillment] could not transition order #{@order.id}: #{e.message}")
        end
      end

      fulfillment.reload
    end

    private

    BLOCKED_ORDER_STATES = %w[cancelled].freeze
    BLOCKED_FINANCIAL_STATES = %w[voided refunded].freeze

    def ensure_order_shippable!
      if BLOCKED_ORDER_STATES.include?(@order.status.to_s)
        raise InvalidInput, "Cannot create a shipment for a #{@order.status} order."
      end
      if BLOCKED_FINANCIAL_STATES.include?(@order.financial_status.to_s)
        raise InvalidInput,
              "Cannot create a shipment for an order with financial_status=#{@order.financial_status}."
      end
    end

    def fulfillment_rows
      rows = @line_items.presence
      return rows if rows.present?

      @order.line_items.map do |line_item|
        remaining = [ line_item.quantity.to_i - line_item.fulfilled_quantity.to_i, 0 ].max
        next if remaining <= 0

        { order_line_item_id: line_item.id, quantity: remaining }
      end.compact
    end

    # Normalize raw input rows to canonical { order_line_item_id:, quantity: }
    # tuples, dropping unknown line item ids and non-positive quantities, and
    # aggregating multiple rows that target the same line item.
    def normalized_rows
      by_oli = Hash.new(0)
      fulfillment_rows.each do |row|
        oli_id = row[:order_line_item_id] || row["order_line_item_id"]
        qty    = (row[:quantity] || row["quantity"]).to_i
        next if qty <= 0
        next unless @order.line_items.exists?(id: oli_id)
        by_oli[oli_id] += qty
      end
      by_oli.map { |oli_id, qty| { order_line_item_id: oli_id, quantity: qty } }
    end

    # Raises AlreadyFulfilled if any line item would be fulfilled beyond its
    # ordered quantity. Re-reads `fulfilled_quantity` from the database to avoid
    # race conditions against concurrent fulfillments.
    def ensure_not_over_fulfilled!(rows)
      return if rows.empty?
      ids = rows.map { |r| r[:order_line_item_id] }
      olis = @order.line_items.where(id: ids).index_by(&:id)
      offenders = rows.filter_map do |row|
        oli = olis[row[:order_line_item_id]]
        next unless oli
        remaining = [ oli.quantity.to_i - oli.fulfilled_quantity.to_i, 0 ].max
        if row[:quantity] > remaining
          { line_item_id: oli.id, sku: oli.sku, requested: row[:quantity], remaining: remaining }
        end
      end
      return if offenders.empty?
      raise AlreadyFulfilled,
            "Cannot fulfill more than ordered. Already fulfilled lines: #{offenders.map { |o| "#{o[:sku] || o[:line_item_id]} (requested #{o[:requested]}, only #{o[:remaining]} remaining)" }.join('; ')}"
    end

    def should_transition_order?
      return true unless @order.source.in?(%w[manual showroom])

      @order.reload.line_items.all? do |line_item|
        line_item.fulfilled_quantity.to_i >= line_item.quantity.to_i
      end
    end
  end
end
