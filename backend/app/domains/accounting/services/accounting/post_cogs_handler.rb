module Accounting
  # Posts COGS journal for a fulfilled shipment.
  #
  #   DR  5000  Cost of Goods Sold      (sum of variant cost * qty)
  #   CR  1200  Inventory               (same total)
  #
  # Idempotent per fulfillment (uses idempotency_key = "cogs-{fulfillment.id}").
  # Skips if no variants have configured or historical cost (total = 0).
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
        variant = fli.order_line_item&.variant
        cost = variant&.cost.presence || variant&.cost_per_item.presence || variant&.last_purchase_cost || 0
        cost * fli.quantity.to_i
      end

      return if total <= 0

      currency = @fulfillment.order.currency.presence || "EGP"

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
