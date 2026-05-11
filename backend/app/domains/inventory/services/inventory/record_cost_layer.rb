module Inventory
  class RecordCostLayer
    def self.call(...)
      new(...).call
    end

    def initialize(stock_item:, quantity:, unit_cost:, source:, received_at: Time.current, details: {})
      @stock_item = stock_item
      @quantity = quantity.to_i
      @unit_cost = unit_cost.to_d
      @source = source
      @received_at = received_at || Time.current
      @details = details || {}
    end

    def call
      return nil if @quantity <= 0 || @unit_cost.negative?

      stock_item = StockItem.find(@stock_item.id)
      StockCostLayer.create!(
        stock_item: stock_item,
        variant_id: stock_item.variant_id,
        warehouse_id: stock_item.warehouse_id,
        received_at: @received_at,
        quantity_received: @quantity,
        qty_remaining: @quantity,
        unit_cost: @unit_cost,
        source_type: source_type,
        source_id: source_id,
        details: @details
      )
    end

    private

    def source_type
      @source.class.name
    end

    def source_id
      @source.respond_to?(:id) ? @source.id.to_s : @source.to_s
    end
  end
end