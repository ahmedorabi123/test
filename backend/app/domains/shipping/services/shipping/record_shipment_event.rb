module Shipping
  class RecordShipmentEvent
    def self.call(fulfillment, kind:, payload: {}, actor: nil, dedupe_key: nil)
      new(fulfillment, kind: kind, payload: payload, actor: actor, dedupe_key: dedupe_key).call
    end

    def initialize(fulfillment, kind:, payload:, actor:, dedupe_key:)
      @fulfillment = fulfillment
      @kind = kind.to_s
      @payload = payload || {}
      @actor = actor
      @dedupe_key = dedupe_key.presence || default_dedupe_key
    end

    def call
      ShipmentEvent.create_or_find_by!(dedupe_key: @dedupe_key) do |event|
        event.fulfillment = @fulfillment
        event.kind = @kind
        event.payload = @payload
        event.actor = @actor
      end
    end

    private

    def default_dedupe_key
      timestamp = @payload[:shopify_updated_at] || @payload["shopify_updated_at"] || Time.current.to_f
      "shipment-event:#{@fulfillment.id}:#{@kind}:#{timestamp}"
    end
  end
end