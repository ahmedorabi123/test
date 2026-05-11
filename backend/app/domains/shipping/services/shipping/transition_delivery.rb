module Shipping
  # Drives Fulfillment#delivery_status through its allowed state graph:
  #
  #   pending ─▶ in_transit ─▶ delivered
  #                       └─▶ failed
  #
  # Idempotent: calling with the same `to:` as the current state is a no-op.
  # Side effects per transition:
  #   - in_transit: stamps `in_transit_at`
  #   - delivered:  stamps `delivered_at`
  #   - records a ShipmentEvent (kind: `in_transit` / `delivered` / `failed`)
  #   - the after_save hook on Fulfillment denormalises `orders.last_delivery_status`
  class TransitionDelivery
    class InvalidTransition < StandardError; end

    LEGAL = {
      "pending"    => %w[in_transit delivered failed],
      "in_transit" => %w[delivered failed],
      "delivered"  => [],
      "failed"     => []
    }.freeze

    def self.call(fulfillment, to:, actor: nil, note: nil)
      new(fulfillment, to: to, actor: actor, note: note).call
    end

    def initialize(fulfillment, to:, actor: nil, note: nil)
      @fulfillment = fulfillment
      @to          = to.to_s
      @actor       = actor
      @note        = note
    end

    def call
      from = (@fulfillment.delivery_status || "pending").to_s
      return @fulfillment if from == @to

      unless ::Fulfillment::DELIVERY_STATUSES.include?(@to)
        raise InvalidTransition, "Unknown delivery_status '#{@to}'"
      end
      unless LEGAL.fetch(from, []).include?(@to)
        raise InvalidTransition, "Illegal delivery transition #{from} → #{@to}"
      end

      ::Fulfillment.transaction do
        attrs = { delivery_status: @to }
        attrs[:in_transit_at] = Time.current if @to == "in_transit" && @fulfillment.in_transit_at.blank?
        attrs[:delivered_at]  = Time.current if @to == "delivered"  && @fulfillment.delivered_at.blank?
        @fulfillment.update!(attrs)

        ::Shipping::RecordShipmentEvent.call(
          @fulfillment,
          kind:       @to,
          payload:    { from: from, to: @to, note: @note }.compact,
          actor:      @actor,
          dedupe_key: "delivery-transition:#{@fulfillment.id}:#{from}->#{@to}"
        )

        AuditLog.record(
          user: @actor,
          action: "fulfillment.delivery_status_changed",
          subject: @fulfillment,
          diff: { delivery_status: { from: from, to: @to } }
        ) if defined?(AuditLog)
      end

      @fulfillment.reload
    end
  end
end
