module Accounting
  # Posts a journal entry for a partial refund. One entry per Refund record
  # (idempotent via idempotency_key). Mirrors PostSaleJournalHandler but in
  # the opposite direction and scoped to the refund amount.
  #
  # Simplified lines (mirror of sale):
  #   DR  4000 Sales Revenue         (subtotal refunded)
  #   DR  2200 Sales Tax Payable     (tax portion, if any)
  #   DR  4100 Shipping Revenue      (shipping refund portion, if any)
  #   CR  1100 Accounts Receivable   (total refund amount)
  #
  # For Shopify refunds we typically only know the total amount + line
  # subtotals; we approximate the tax share proportionally.
  class PartialRefundJournalHandler
    IDEMPOTENCY_PREFIX = "refund-partial".freeze

    def self.call(refund)
      new(refund).call
    end

    def initialize(refund)
      @refund = refund
    end

    def call
      return if @refund.amount.to_d <= 0

      idem_key = "#{IDEMPOTENCY_PREFIX}-#{@refund.id}"
      return if JournalEntry.exists?(idempotency_key: idem_key)

      lines = build_lines
      return if lines.empty?

      JournalEntry.post!(
        {
          entry_date:      (@refund.processed_at&.to_date || Date.current),
          description:     "Partial refund – #{@refund.order.order_number}",
          currency:        @refund.currency.presence || @refund.order.currency.presence || "EGP",
          source_type:     "refund",
          source_id:       @refund.id,
          entry_type:      "refund",
          idempotency_key: idem_key
        },
        lines
      )
    end

    private

    def build_lines
      total_refund = @refund.amount.to_d
      return [] if total_refund <= 0

      subtotal_refunded = @refund.refund_line_items.sum(:subtotal).to_d
      # If we don't have line-level subtotals, assume the whole amount is revenue reversal.
      subtotal_refunded = total_refund if subtotal_refunded <= 0

      # Estimate the tax share based on the order's tax-to-subtotal ratio.
      order     = @refund.order
      base      = order.subtotal_price.to_d + order.total_shipping.to_d
      tax_ratio = base.positive? ? (order.total_tax.to_d / base) : 0.to_d
      tax_part  = (subtotal_refunded * tax_ratio).round(2)

      # Remainder (if any) counts as shipping or misc credit reversal.
      accounted = subtotal_refunded + tax_part
      misc      = (total_refund - accounted).round(2)
      shipping_part = [misc, 0].max

      lines = []
      lines << { account_code: "4000", side: "debit",  amount: subtotal_refunded,
                 description: "Revenue reversal – #{order.order_number}" } if subtotal_refunded > 0
      lines << { account_code: "2200", side: "debit",  amount: tax_part,
                 description: "Tax reversal" } if tax_part > 0
      lines << { account_code: "4100", side: "debit",  amount: shipping_part,
                 description: "Shipping reversal" } if shipping_part > 0

      total_debits = lines.sum { |l| l[:amount] }
      return [] if total_debits <= 0

      lines << { account_code: "1100", side: "credit", amount: total_debits,
                 description: "Refund issued – #{order.order_number}" }
      lines
    end
  end
end
