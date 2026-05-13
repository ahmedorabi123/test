module Accounting
  # Posts the journal entry for the negative rows of a showroom sales report.
  #
  # Negative rows are treated as accounting-only sales reversals: they do NOT
  # create a +Refund+ record, they do NOT move physical stock, and they do
  # NOT create an +OrderLineItem+. They represent the customer-side reversal
  # of a previously-recognised sale.
  #
  # Journal (mirrors a sale, reversed):
  #   DR 4000  Sales Revenue       (reversal amount)
  #   CR 1100  A/R / Cash          (reversal amount)
  #
  # Idempotent on +ShowroomReversal#idempotency_key+ so re-running the same
  # period is a no-op.
  class PostShowroomReversalHandler
    def self.call(reversal)
      new(reversal).call
    end

    def initialize(reversal)
      @reversal = reversal
    end

    def call
      return if @reversal.total_amount.to_d <= 0
      return if JournalEntry.exists?(idempotency_key: @reversal.idempotency_key)

      JournalEntry.post!(
        {
          entry_date:      @reversal.posted_at&.to_date || Date.current,
          description:     "Showroom reversal – #{@reversal.warehouse.name} #{@reversal.period}",
          currency:        @reversal.currency,
          source_type:     "showroom_reversal",
          source_id:       @reversal.id,
          entry_type:      "refund",
          idempotency_key: @reversal.idempotency_key
        },
        [
          { account_code: "4000", side: "debit",  amount: @reversal.total_amount,
            description: "Sales reversal – #{@reversal.warehouse.code} #{@reversal.period}" },
          { account_code: "1100", side: "credit", amount: @reversal.total_amount,
            description: "A/R reversal – showroom #{@reversal.warehouse.code} #{@reversal.period}" }
        ]
      )
    end
  end
end
