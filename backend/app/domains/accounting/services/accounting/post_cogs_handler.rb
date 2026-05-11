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

      zero_cost_lines = []

      total = @fulfillment.fulfillment_line_items.sum do |fli|
        variant = fli.order_line_item&.variant
        result  = Catalog::VariantCostResolver.call(variant)
        if result.zero? && fli.quantity.to_i > 0
          zero_cost_lines << { variant_id: variant&.id, sku: variant&.sku, quantity: fli.quantity.to_i, source: result.source }
        end
        result.cost * fli.quantity.to_i
      end

      if total <= 0
        if zero_cost_lines.any?
          AuditLog.create!(
            action:       "cogs.skipped_zero_cost",
            subject_type: @fulfillment.class.name,
            subject_id:   @fulfillment.id,
            diff:         { order_id: @fulfillment.order_id, order_number: @fulfillment.order&.order_number, lines: zero_cost_lines },
            occurred_at:  Time.current
          )
        end
        return
      end

      if zero_cost_lines.any?
        AuditLog.create!(
          action:       "cogs.partial_zero_cost",
          subject_type: @fulfillment.class.name,
          subject_id:   @fulfillment.id,
          diff:         { order_id: @fulfillment.order_id, order_number: @fulfillment.order&.order_number, lines: zero_cost_lines },
          occurred_at:  Time.current
        )
      end

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
