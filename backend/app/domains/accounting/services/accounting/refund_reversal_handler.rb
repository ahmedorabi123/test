module Accounting
  # Reverses the sale journal entry when an order is refunded.
  #
  # Two callers:
  #   * Refund/Shopify path: financial_status moves to "refunded" -> default
  #     idempotency key "refund-reversal-<order_id>".
  #   * Order cancellation while paid: passes force: true. We still post a
  #     reversal (otherwise the sale journal stays open on a cancelled order),
  #     but use a distinct idempotency key "cancel-reversal-<order_id>" so
  #     subsequent refund processing can still post its own reversal if needed.
  class RefundReversalHandler
    IDEMPOTENCY_PREFIX        = "refund-reversal".freeze
    CANCEL_IDEMPOTENCY_PREFIX = "cancel-reversal".freeze

    def self.call(order, force: false)
      new(order, force: force).call
    end

    def initialize(order, force: false)
      @order = order
      @force = force
    end

    def call
      unless @force || %w[refunded].include?(@order.financial_status)
        return
      end

      idem_prefix = @force ? CANCEL_IDEMPOTENCY_PREFIX : IDEMPOTENCY_PREFIX
      idem_key = "#{idem_prefix}-#{@order.id}"
      return if JournalEntry.exists?(idempotency_key: idem_key)

      # Find the original sale journal entry
      original = JournalEntry.find_by(
        source_type: "order",
        source_id:   @order.id,
        entry_type:  "sale",
        status:      "posted"
      )
      return unless original

      description = @force ? "Cancellation reversal" : "Refund reversal"
      reversal = original.reverse!(
        description: "#{description} – #{@order.order_number}"
      )
      # Tag the reversal with its own idempotency key
      reversal.update_columns(idempotency_key: idem_key)
      reversal
    end
  end
end
