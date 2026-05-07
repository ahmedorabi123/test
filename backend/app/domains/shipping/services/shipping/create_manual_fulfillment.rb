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

      fulfillment = nil
      ApplicationRecord.transaction do
        fulfillment = Fulfillment.create!(
          order:            @order,
          status:           "success",
          tracking_company: @tracking_company,
          tracking_number:  @tracking_number,
          tracking_url:     @tracking_url,
          service:          @service,
          shipped_at:       @shipped_at
        )

        fulfillment_rows.each do |row|
          oli_id = row[:order_line_item_id] || row["order_line_item_id"]
          qty    = (row[:quantity] || row["quantity"]).to_i
          next if qty <= 0
          oli = @order.line_items.find_by(id: oli_id)
          next unless oli
          fulfillment.fulfillment_line_items.create!(
            order_line_item_id: oli.id,
            quantity:           qty
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

      if @transition_order && @order.status != "fulfilled"
        begin
          ::Sales::OrderStateMachine.call(@order.reload, to: "fulfilled", actor: @actor)
        rescue ::Sales::OrderStateMachine::InvalidTransition => e
          Rails.logger.warn("[CreateManualFulfillment] could not transition order #{@order.id}: #{e.message}")
        end
      end

      fulfillment.reload
    end

    private

    def fulfillment_rows
      rows = @line_items.presence
      return rows if rows.present?

      @order.line_items.map do |line_item|
        remaining = [line_item.quantity.to_i - line_item.fulfilled_quantity.to_i, 0].max
        next if remaining <= 0

        { order_line_item_id: line_item.id, quantity: remaining }
      end.compact
    end
  end
end
