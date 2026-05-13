module Inventory
  class ProvisionStockItems
    def self.call(variant: nil, product: nil, warehouses: nil)
      new(variant: variant, product: product, warehouses: warehouses).call
    end

    def initialize(variant:, product:, warehouses:)
      @variant = variant
      @product = product
      @warehouses = warehouses
    end

    def call
      variants.each do |variant|
        target_warehouses.find_each do |warehouse|
          provision_stock_item(variant, warehouse)
        end
      end
    end

    private

    def variants
      return Variant.where(id: @variant.id) if @variant
      return @product.variants if @product

      Variant.none
    end

    def target_warehouses
      return eligible_warehouses.merge(@warehouses) if @warehouses

      eligible_warehouses
    end

    def eligible_warehouses
      Warehouse.active.own.where.not(kind: %w[consignment transit])
    end

    def provision_stock_item(variant, warehouse)
      now = Time.current
      row = {
        variant_id: variant.id,
        warehouse_id: warehouse.id,
        quantity_on_hand: 0,
        quantity_reserved: 0,
        low_stock_threshold: 0,
        created_at: now,
        updated_at: now
      }
      row[:quantity_unavailable] = 0 if StockItem.column_names.include?("quantity_unavailable")

      StockItem.insert_all(
        [row],
        unique_by: :index_stock_items_on_variant_id_and_warehouse_id
      )
    end
  end
end
