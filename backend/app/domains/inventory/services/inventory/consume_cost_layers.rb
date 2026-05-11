module Inventory
  class ConsumeCostLayers
    Result = Struct.new(:total_cost, :layers_used, :source, keyword_init: true) do
      def zero?
        total_cost.to_d <= 0
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(stock_item:, quantity:, reference: nil)
      @stock_item = stock_item
      @quantity = quantity.to_i
      @reference = reference
    end

    def call
      return Result.new(total_cost: 0.to_d, layers_used: [], source: "none") if @quantity <= 0

      used = []
      remaining = @quantity

      StockCostLayer.transaction do
        stock_item = StockItem.lock.find(@stock_item.id)
        StockCostLayer.open.where(stock_item_id: stock_item.id).fifo.lock.each do |layer|
          break if remaining <= 0

          take = [layer.qty_remaining.to_i, remaining].min
          next if take <= 0

          layer.update!(qty_remaining: layer.qty_remaining.to_i - take)
          used << layer_payload(layer, take)
          remaining -= take
        end

        append_fallback_cost!(stock_item, remaining, used) if remaining.positive?
        persist_breakdown!(used)
      end

      Result.new(
        total_cost: used.sum { |row| row[:total_cost].to_d }.round(2),
        layers_used: used,
        source: used.any? { |row| row[:source] == "fifo" } ? "fifo" : "fallback"
      )
    end

    private

    def layer_payload(layer, quantity)
      total = (layer.unit_cost.to_d * quantity).round(2)
      {
        source: "fifo",
        layer_id: layer.id,
        quantity: quantity,
        unit_cost: layer.unit_cost.to_d.to_s,
        total_cost: total.to_s,
        source_type: layer.source_type,
        source_id: layer.source_id
      }
    end

    def append_fallback_cost!(stock_item, quantity, used)
      result = Catalog::VariantCostResolver.call(stock_item.variant)
      return if result.zero?

      total = (result.cost.to_d * quantity).round(2)
      used << {
        source: result.source,
        layer_id: nil,
        quantity: quantity,
        unit_cost: result.cost.to_d.to_s,
        total_cost: total.to_s,
        source_type: "Catalog::VariantCostResolver",
        source_id: stock_item.variant_id
      }
    end

    def persist_breakdown!(used)
      return unless @reference&.respond_to?(:cost_breakdown=)

      @reference.update!(cost_breakdown: used)
    end
  end
end