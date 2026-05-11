module Accounting
  # Reverses COGS for a refund that physically restocked inventory.
  #
  #   DR  1200  Inventory                 (sum of variant cost * restocked qty)
  #   CR  5000  Cost of Goods Sold        (same total)
  #
  # Only reverses lines that were actually restocked (`restock_type == "return"`
  # for Shopify refunds, or `refund.restock?` for manual refunds without an
  # explicit per-line type). Skips lines with no restock or zero cost.
  #
  # Idempotent per refund (idempotency_key = "cogs-reversal-{refund.id}").
  # No-op if total reversal amount is zero (no restocked lines or no costs).
  class PostCogsReversalHandler
    IDEMPOTENCY_PREFIX = "cogs-reversal".freeze

    def self.call(refund)
      new(refund).call
    end

    def initialize(refund)
      @refund = refund
    end

    def call
      return unless @refund
      return unless @refund.processed?

      idem_key = "#{IDEMPOTENCY_PREFIX}-#{@refund.id}"
      return if JournalEntry.exists?(idempotency_key: idem_key)

      zero_cost_lines = []

      total = restockable_lines.sum do |rli|
        variant = rli.order_line_item&.variant
        result  = Catalog::VariantCostResolver.call(variant)
        if result.zero? && rli.quantity.to_i > 0
          zero_cost_lines << { variant_id: variant&.id, sku: variant&.sku, quantity: rli.quantity.to_i, source: result.source }
        end
        result.cost * rli.quantity.to_i
      end

      if total <= 0
        if zero_cost_lines.any?
          AuditLog.create!(
            action:       "cogs_reversal.skipped_zero_cost",
            subject_type: @refund.class.name,
            subject_id:   @refund.id,
            diff:         { order_id: @refund.order_id, lines: zero_cost_lines },
            occurred_at:  Time.current
          )
        end
        return
      end

      if zero_cost_lines.any?
        AuditLog.create!(
          action:       "cogs_reversal.partial_zero_cost",
          subject_type: @refund.class.name,
          subject_id:   @refund.id,
          diff:         { order_id: @refund.order_id, lines: zero_cost_lines },
          occurred_at:  Time.current
        )
      end

      order = @refund.order
      currency = order&.currency.presence || "EGP"

      JournalEntry.post!(
        {
          entry_date:      Date.current,
          description:     "COGS reversal – #{order&.order_number} refund #{@refund.id}",
          currency:        currency,
          source_type:     "refund",
          source_id:       @refund.id,
          entry_type:      "refund",
          idempotency_key: idem_key
        },
        [
          { account_code: "1200", side: "debit",  amount: total,
            description: "Inventory restocked – refund #{@refund.id}" },
          { account_code: "5000", side: "credit", amount: total,
            description: "COGS reversal – refund #{@refund.id}" }
        ]
      )
    end

    private

    def restockable_lines
      @refund.refund_line_items.select do |rli|
        next false if rli.quantity.to_i <= 0
        next false unless rli.order_line_item

        rt = rli.restock_type.to_s
        if rt.present?
          rt == "return"
        else
          # Manual refunds may leave restock_type nil; fall back to refund-level flag.
          @refund.restock? || @refund.inventory_restocked?
        end
      end
    end

    def variant_cost(variant)
      Catalog::VariantCostResolver.call(variant).cost
    end
  end
end
