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
      return unless Accounting::Features.cogs_enabled?
      return unless @refund
      return unless @refund.processed?

      idem_key = "#{IDEMPOTENCY_PREFIX}-#{@refund.id}"
      return if JournalEntry.exists?(idempotency_key: idem_key)

      zero_cost_lines = []

      total = restockable_lines.sum do |rli|
        variant = rli.order_line_item&.variant
        result  = cost_result_for(rli, variant)
        if result.zero? && rli.quantity.to_i > 0
          zero_cost_lines << { variant_id: variant&.id, sku: variant&.sku, quantity: rli.quantity.to_i, source: result.source }
        end
        result.total_cost
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

    CostResult = Struct.new(:total_cost, :source, keyword_init: true) do
      def zero?
        total_cost.to_d <= 0
      end
    end

    def cost_result_for(refund_line_item, variant)
      breakdown = Array(refund_line_item.cost_breakdown)
      if breakdown.any?
        return CostResult.new(
          total_cost: breakdown.sum { |row| row.to_h.with_indifferent_access[:total_cost].to_d }.round(2),
          source: "fifo_restore"
        )
      end

      original = original_fulfillment_breakdown(refund_line_item)
      if original.any?
        unit_total = original.sum { |row| row[:unit_cost].to_d * row[:quantity].to_i }
        quantity = original.sum { |row| row[:quantity].to_i }
        unit_cost = quantity.positive? ? (unit_total / quantity).round(4) : 0.to_d
        return CostResult.new(
          total_cost: (unit_cost * refund_line_item.quantity.to_i).round(2),
          source: "fifo"
        )
      end

      result = Catalog::VariantCostResolver.call(variant)
      CostResult.new(
        total_cost: (result.cost.to_d * refund_line_item.quantity.to_i).round(2),
        source: result.source
      )
    end

    def original_fulfillment_breakdown(refund_line_item)
      refund_line_item.order_line_item&.fulfillment_line_items&.flat_map do |fulfillment_line_item|
        Array(fulfillment_line_item.cost_breakdown).map { |row| row.to_h.with_indifferent_access }
      end || []
    end
  end
end
