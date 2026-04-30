module Manufacturing
  # Runs a production order:
  # - validates components available
  # - consumes components (reason: consumed)
  # - produces parent (reason: manufactured)
  # Atomic via transaction.
  class ProductionRunner
    class Error < StandardError; end

    def self.call(production_order)
      new(production_order).call
    end

    def initialize(production_order)
      @po = production_order
    end

    def call
      raise Error, "Production order must be draft or in_progress" \
        unless %w[draft in_progress].include?(@po.status)

      explode = Catalog::Bom.explode_full(@po.parent_variant_id, units: @po.quantity)
      raise Error, "Variant has no BOM defined" if explode.empty?

      # In staged mode, all stages must be completed before the parent can be produced
      if @po.staged? && @po.production_stages.where.not(status: %w[completed skipped]).exists?
        raise Error, "All production stages must be completed before finalizing"
      end

      ApplicationRecord.transaction do
        @po.update!(status: "in_progress", started_at: @po.started_at || Time.current)

        consume_components!(explode)
        produce_parent!

        @po.update!(status: "completed", completed_at: Time.current)
      end

      @po
    end

    private

    def consume_components!(explode)
      explode.each do |variant_id, qty|
        stock_item = StockItem.find_by(variant_id: variant_id, warehouse_id: @po.warehouse_id)
        raise Error, "Component #{variant_id} not stocked at warehouse" unless stock_item
        raise Error, "Insufficient stock for component #{variant_id}" if stock_item.available < qty

        Inventory::WriteMovement.call(
          stock_item: stock_item,
          delta:      -qty,
          reason:     "consumed",
          reference:  "production:#{@po.id}",
          strict:     true
        )
      end
    end

    def produce_parent!
      parent_item = StockItem.find_or_create_by!(
        variant_id:   @po.parent_variant_id,
        warehouse_id: @po.warehouse_id
      )

      Inventory::WriteMovement.call(
        stock_item: parent_item,
        delta:      @po.quantity,
        reason:     "manufactured",
        reference:  "production:#{@po.id}"
      )
    end
  end
end
