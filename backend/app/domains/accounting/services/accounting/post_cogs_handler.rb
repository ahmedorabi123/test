module Accounting
  # Posts COGS journal for a fulfilled shipment.
  #
  #   DR  5000  Cost of Goods Sold      (sum of cost_per_item * qty)
  #   CR  1200  Inventory               (same total)
  #
  # Idempotent per fulfillment (uses idempotency_key = "cogs-{fulfillment.id}").
  # Skips if no variants have cost_per_item configured (total = 0).
  class PostCogsHandler
    IDEMPOTENCY_PREFIX = "cogs".freeze

    def self.call(fulfillment)
      new(fulfillment).call
    end

    def initialize(fulfillment)
      @fulfillment = fulfillment
    end

    def call
      return if @fulfillment.status != "success"

      idem_key = "#{IDEMPOTENCY_PREFIX}-#{@fulfillment.id}"
      return if JournalEntry.exists?(idempotency_key: idem_key)

      total = @fulfillment.fulfillment_line_items.sum do |fli|
        cost = fli.order_line_item&.variant&.cost_per_item.to_d
        cost * fli.quantity.to_i
      end

      return if total <= 0

      currency = @fulfillment.order.currency.presence || "USD"

      JournalEntry.post!(
        {
          entry_date:      Date.current,
          description:     "COGS – #{@fulfillment.order.order_number} fulfillment",
          currency:        currency,
          source_type:     "fulfillment",
          source_id:       @fulfillment.id,
          entry_type:      "sale",
          idempotency_key: idem_key
        },
        [
          { account_code: "5000", side: "debit",  amount: total,
            description: "COGS – #{@fulfillment.order.order_number}" },
          { account_code: "1200", side: "credit", amount: total,
            description: "Inventory consumed – #{@fulfillment.order.order_number}" }
        ]
      )
    end
  end
end
