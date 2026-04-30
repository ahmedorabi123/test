module Catalog
  # Explodes BOM: returns { component_variant_id => required_quantity }
  # for assembling a given number of parent units, accounting for waste_factor.
  #
  # Assumes a single level (not recursive sub-assemblies). Recursive explosion
  # can be added later if needed.
  class Bom
    class << self
      def components_for(parent_variant_id)
        BomItem.where(parent_variant_id: parent_variant_id).includes(:component_variant)
      end

      def has_bom?(parent_variant_id)
        BomItem.where(parent_variant_id: parent_variant_id).exists?
      end

      # Returns Hash: variant_id => required_quantity (Integer ceiled)
      def explode(parent_variant_id, units:)
        raise ArgumentError, "units must be positive" if units.to_i <= 0

        components_for(parent_variant_id).each_with_object({}) do |bi, h|
          needed = bi.quantity * units
          # waste_factor grows the requirement:
          #   required = needed / (1 - waste_factor)
          wf = bi.waste_factor.to_d
          required = wf.positive? ? (needed / (1 - wf)) : needed
          h[bi.component_variant_id] = required.ceil
        end
      end

      # Recursively explodes multi-level BOM until reaching leaf components
      # (variants that have no further BOM definition). Sub-assembly quantities
      # are folded into their leaf parts.
      #
      # Returns Hash: leaf_variant_id => total_required_quantity (Integer ceiled)
      def explode_full(parent_variant_id, units:, _seen: nil)
        raise ArgumentError, "units must be positive" if units.to_i <= 0

        seen = _seen || Set.new
        if seen.include?(parent_variant_id)
          raise ArgumentError, "BOM cycle detected at variant #{parent_variant_id}"
        end
        seen = seen.dup << parent_variant_id

        result = Hash.new(0)
        bi_rows = components_for(parent_variant_id)
        return result if bi_rows.empty?

        bi_rows.each do |bi|
          needed = bi.quantity.to_d * units.to_d
          wf = bi.waste_factor.to_d
          required = wf.positive? ? (needed / (1 - wf)) : needed

          if has_bom?(bi.component_variant_id)
            sub = explode_full(bi.component_variant_id, units: required.ceil, _seen: seen)
            sub.each { |cv_id, qty| result[cv_id] += qty }
          else
            result[bi.component_variant_id] += required.ceil
          end
        end

        result.transform_values(&:to_i)
      end

      # Returns Boolean: whether we have enough of every component in the given
      # warehouse to assemble `units` of parent_variant_id.
      def can_assemble?(parent_variant_id, units:, warehouse_id:)
        explode(parent_variant_id, units: units).all? do |cv_id, required|
          item = StockItem.find_by(variant_id: cv_id, warehouse_id: warehouse_id)
          next false unless item
          item.available >= required
        end
      end

      # Returns Hash: variant_id => { required:, on_hand:, shortfall: }
      def shortfall(parent_variant_id, units:, warehouse_id:)
        explode(parent_variant_id, units: units).transform_values do |required|
          # placeholder; not used — actual keys are component ids
          required
        end.each_with_object({}) do |(cv_id, required), h|
          item = StockItem.find_by(variant_id: cv_id, warehouse_id: warehouse_id)
          on_hand = item&.available.to_i
          h[cv_id] = {
            required:  required,
            on_hand:   on_hand,
            shortfall: [required - on_hand, 0].max
          }
        end
      end
    end
  end
end
