module Shipping
  # Creates a manual Fulfillment record (no Shopify) for an order.
  # Optionally transitions the order to "fulfilled" which deducts inventory
  # and posts COGS via Sales::OrderStateMachine.
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

        @line_items.each do |row|
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

      if @transition_order && @order.status != "fulfilled"
        begin
          ::Sales::OrderStateMachine.call(@order.reload, to: "fulfilled", actor: @actor)
        rescue ::Sales::OrderStateMachine::InvalidTransition => e
          Rails.logger.warn("[CreateManualFulfillment] could not transition order #{@order.id}: #{e.message}")
        end
      end

      fulfillment.reload
    end
  end
end
