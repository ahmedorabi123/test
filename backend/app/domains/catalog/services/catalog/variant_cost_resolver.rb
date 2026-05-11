module Catalog
  # Resolves the unit cost of a variant for COGS postings.
  #
  # Priority (first non-nil, > 0 wins):
  #   1. variant.cost
  #   2. variant.cost_per_item
  #   3. variant.last_purchase_cost
  #   4. weighted average of received purchase order line items
  #        SUM(unit_cost * quantity_received) / SUM(quantity_received)
  #   5. 0 (caller MUST handle the zero-cost case — usually by writing an
  #      AuditLog entry rather than silently dropping the COGS posting)
  #
  # Returns a BigDecimal/Numeric. Never raises.
  class VariantCostResolver
    Result = Struct.new(:cost, :source, keyword_init: true) do
      def zero?
        cost.to_d <= 0
      end
    end

    def self.call(variant)
      new(variant).call
    end

    def initialize(variant)
      @variant = variant
    end

    def call
      return Result.new(cost: 0, source: :missing_variant) if @variant.nil?

      if (c = positive(@variant.cost))
        return Result.new(cost: c, source: :variant_cost)
      end
      if (c = positive(@variant.cost_per_item))
        return Result.new(cost: c, source: :variant_cost_per_item)
      end
      if (c = positive(@variant.last_purchase_cost))
        return Result.new(cost: c, source: :last_purchase_cost)
      end
      if (c = weighted_avg_purchase_cost)
        return Result.new(cost: c, source: :weighted_avg_purchase)
      end

      Result.new(cost: 0, source: :zero_fallback)
    end

    private

    def positive(value)
      return nil if value.nil?
      dec = value.to_d
      dec > 0 ? dec : nil
    end

    def weighted_avg_purchase_cost
      return nil unless defined?(::PurchaseOrderLineItem)

      scope = ::PurchaseOrderLineItem
              .where(variant_id: @variant.id)
              .where("quantity_received > 0")
      total_qty  = scope.sum(:quantity_received)
      return nil if total_qty.to_i <= 0

      total_cost = scope.sum("unit_cost * quantity_received")
      avg = (total_cost.to_d / total_qty.to_d)
      avg > 0 ? avg : nil
    rescue StandardError
      nil
    end
  end
end
