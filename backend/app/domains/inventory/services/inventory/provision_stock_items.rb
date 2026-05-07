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
          StockItem.create_or_find_by!(variant: variant, warehouse: warehouse) do |stock_item|
            stock_item.quantity_on_hand = 0
            stock_item.quantity_reserved = 0
            stock_item.quantity_unavailable = 0 if stock_item.respond_to?(:quantity_unavailable=)
            stock_item.low_stock_threshold = 0
          end
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
      @warehouses || Warehouse.active.own
    end
  end
end