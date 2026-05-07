module Accounting
  # Posts the double-entry journal for a completed (paid) sale.
  #
  # Accounts used (seeded in COA):
  #   DR  1100  Accounts Receivable / Cash          (revenue)
  #   CR  4000  Sales Revenue                       (revenue)
  #   DR  2200  Sales Tax Payable  (if tax > 0)     (liability)
  #   CR  2200  Sales Tax Payable                   (credit side of tax)
  #
  # Simplified two-line entry:
  #   DR  1100  total_price
  #   CR  4000  subtotal_price
  #   CR  2200  total_tax           (if any)
  #   CR  4100  Shipping Revenue    (if any)
  #
  class PostSaleJournalHandler
    IDEMPOTENCY_PREFIX = "sale-journal".freeze

    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      # Accept paid, partially_refunded, and refunded — all represent orders where
      # a sale occurred. For refunded orders the sale journal is subsequently reversed
      # by RefundReversalHandler. Idempotency key prevents double-posting.
      return unless %w[paid partially_refunded refunded].include?(@order.financial_status)

      idem_key = "#{IDEMPOTENCY_PREFIX}-#{@order.id}"
      return if JournalEntry.exists?(idempotency_key: idem_key)

      lines = build_lines
      return if lines.empty?

      JournalEntry.post!(
        {
          entry_date:       (@order.placed_at&.to_date || Date.current),
          description:      "Sale #{@order.order_number}",
          currency:         @order.currency.presence || "EGP",
          source_type:      "order",
          source_id:        @order.id,
          entry_type:       "sale",
          idempotency_key:  idem_key
        },
        lines
      )
    end

    private

    def build_lines
      lines = []

      subtotal  = @order.subtotal_price.to_d
      tax       = @order.total_tax.to_d
      shipping  = @order.total_shipping.to_d
      discount  = @order.total_discount.to_d
      total_dr  = subtotal + tax + shipping - discount

      return [] if total_dr <= 0

      lines << { account_code: "1100", side: "debit",  amount: total_dr,
                 description: "A/R – #{@order.customer_name || @order.customer_email}" }
      lines << { account_code: "4000", side: "credit", amount: subtotal - discount,
                 description: "Sales revenue – #{@order.order_number}" }
      lines << { account_code: "2200", side: "credit", amount: tax,
                 description: "Sales tax payable" } if tax > 0
      lines << { account_code: "4100", side: "credit", amount: shipping,
                 description: "Shipping revenue" } if shipping > 0

      lines
    end
  end
end
