module Sales
  class RefundStateMachine
    class InvalidTransition < StandardError; end

    LEGAL = {
      "draft" => %w[approved cancelled processed],
      "approved" => %w[processed cancelled],
      "processed" => [],
      "cancelled" => []
    }.freeze

    def self.call(refund, to:, actor: nil)
      new(refund, to: to, actor: actor).call
    end

    def initialize(refund, to:, actor: nil)
      @refund = refund
      @to = to.to_s
      @actor = actor
    end

    def call
      from = @refund.status.to_s
      return @refund if from == @to
      raise InvalidTransition, "Cannot transition Shopify refunds" if @refund.shopify_linked?
      raise InvalidTransition, "Illegal refund transition #{from} -> #{@to}" unless LEGAL.fetch(from, []).include?(@to)

      @refund.update!(status: @to)
      AuditLog.record(user: @actor, action: "refund.transition", subject: @refund, diff: { from: from, to: @to }) if defined?(AuditLog)
      @refund
    end
  end
end