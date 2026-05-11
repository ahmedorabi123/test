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

      total = restockable_lines.sum do |rli|
        variant = rli.order_line_item&.variant
        cost = variant_cost(variant)
        cost * rli.quantity.to_i
      end

      return if total <= 0

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
      return 0 unless variant
      variant.cost.presence || variant.cost_per_item.presence || variant.last_purchase_cost || 0
    end
  end
end
