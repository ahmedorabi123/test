module Inventory
  class RestoreCostLayers
    Result = Struct.new(:total_cost, :layers_used, :source, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(refund_line_item:, stock_item:)
      @refund_line_item = refund_line_item
      @stock_item = stock_item
      @quantity = refund_line_item.quantity.to_i
    end

    def call
      return Result.new(total_cost: 0.to_d, layers_used: [], source: "none") if @quantity <= 0

      used = []
      remaining = @quantity

      original_cost_rows.each do |row|
        break if remaining <= 0

        available = row[:quantity].to_i
        next if available <= 0

        take = [available, remaining].min
        layer = Inventory::RecordCostLayer.call(
          stock_item: @stock_item,
          quantity: take,
          unit_cost: row[:unit_cost].to_d,
          source: @refund_line_item,
          details: { restored_from: row }
        )
        used << restored_payload(layer, row, take)
        remaining -= take
      end

      append_fallback_restore!(remaining, used) if remaining.positive?
      @refund_line_item.update!(cost_breakdown: used) if @refund_line_item.respond_to?(:cost_breakdown=)

      Result.new(
        total_cost: used.sum { |row| row[:total_cost].to_d }.round(2),
        layers_used: used,
        source: used.any? { |row| row[:source] == "fifo_restore" } ? "fifo_restore" : "fallback"
      )
    end

    private

    def original_cost_rows
      rows = @refund_line_item.order_line_item&.fulfillment_line_items&.order(created_at: :desc)&.flat_map do |fli|
        Array(fli.cost_breakdown).map { |row| row.with_indifferent_access }
      end || []
      rows.map do |row|
        {
          layer_id: row[:layer_id],
          quantity: row[:quantity].to_i,
          unit_cost: row[:unit_cost].to_d,
          total_cost: row[:total_cost].to_d,
          source: row[:source]
        }
      end
    end

    def restored_payload(layer, original_row, quantity)
      unit_cost = original_row[:unit_cost].to_d
      {
        source: "fifo_restore",
        layer_id: layer&.id,
        original_layer_id: original_row[:layer_id],
        quantity: quantity,
        unit_cost: unit_cost.to_s,
        total_cost: (unit_cost * quantity).round(2).to_s,
        source_type: "RefundLineItem",
        source_id: @refund_line_item.id
      }
    end

    def append_fallback_restore!(quantity, used)
      result = Catalog::VariantCostResolver.call(@stock_item.variant)
      return if result.zero?

      layer = Inventory::RecordCostLayer.call(
        stock_item: @stock_item,
        quantity: quantity,
        unit_cost: result.cost,
        source: @refund_line_item,
        details: { restored_from: "fallback", source: result.source }
      )
      used << {
        source: result.source,
        layer_id: layer&.id,
        original_layer_id: nil,
        quantity: quantity,
        unit_cost: result.cost.to_d.to_s,
        total_cost: (result.cost.to_d * quantity).round(2).to_s,
        source_type: "Catalog::VariantCostResolver",
        source_id: @stock_item.variant_id
      }
    end
  end
end