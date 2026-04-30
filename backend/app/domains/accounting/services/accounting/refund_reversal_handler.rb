module Accounting
  # Reverses the sale journal entry when an order is refunded.
  class RefundReversalHandler
    IDEMPOTENCY_PREFIX = "refund-reversal".freeze

    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      return unless %w[refunded].include?(@order.financial_status)

      idem_key = "#{IDEMPOTENCY_PREFIX}-#{@order.id}"
      return if JournalEntry.exists?(idempotency_key: idem_key)

      # Find the original sale journal entry
      original = JournalEntry.find_by(
        source_type: "order",
        source_id:   @order.id,
        entry_type:  "sale",
        status:      "posted"
      )
      return unless original

      reversal = original.reverse!(
        description: "Refund reversal – #{@order.order_number}"
      )
      # Tag the reversal with its own idempotency key
      reversal.update_columns(idempotency_key: idem_key)
      reversal
    end
  end
end
