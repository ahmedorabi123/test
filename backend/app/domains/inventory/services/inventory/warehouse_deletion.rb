module Inventory
  class WarehouseDeletion
    Result = Struct.new(:warehouse, :deleted_stock_items, :dependencies, keyword_init: true) do
      def allowed? = dependencies.blank?
    end

    class Blocked < StandardError
      attr_reader :result

      def initialize(result)
        @result = result
        super("Warehouse cannot be deleted because it has business history or inventory dependencies.")
      end
    end

    def self.call(warehouse:, actor: nil)
      new(warehouse: warehouse, actor: actor).call
    end

    def initialize(warehouse:, actor: nil)
      @warehouse = warehouse
      @actor = actor
    end

    def call
      result = Result.new(
        warehouse: @warehouse,
        deleted_stock_items: deletable_stock_item_ids.size,
        dependencies: dependencies
      )
      raise Blocked.new(result) unless result.allowed?

      Warehouse.transaction do
        StockItem.where(id: deletable_stock_item_ids).delete_all

        AuditLog.record(
          user: @actor,
          action: "warehouse.deleted",
          subject: @warehouse,
          diff: { code: @warehouse.code, deleted_stock_items: result.deleted_stock_items }
        )

        @warehouse.destroy!
      end

      result
    end

    private

    def dependencies
      @dependencies ||= begin
        rows = []
        rows << dependency(:shopify_origin, 1, "Shopify-managed warehouses cannot be deleted.") if @warehouse.shopify_origin?
        rows << dependency(:nonzero_stock_items, nonzero_stock_items_count, "Stock must be zero and have no reserved/unavailable quantities.")
        rows << dependency(:stock_reservations, stock_reservations_count, "Active or historical stock reservations still reference this warehouse.")
        rows << dependency(:stock_movements, stock_movements_count, "Stock movement history exists; deactivate the warehouse instead.")
        rows << dependency(:stock_cost_layers, stock_cost_layers_count, "Inventory cost layers exist; deactivate the warehouse instead.")
        rows << dependency(:purchase_orders, purchase_orders_count, "Purchase orders reference this warehouse.")
        rows << dependency(:production_orders, production_orders_count, "Production orders reference this warehouse.")
        rows << dependency(:stock_transfers, stock_transfers_count, "Stock transfers reference this warehouse.")
        rows << dependency(:showroom_reversals, showroom_reversals_count, "Showroom reports reference this warehouse.")
        rows << dependency(:user_roles, user_roles_count, "User role assignments are scoped to this warehouse.")
        rows.compact
      end
    end

    def dependency(key, count, message)
      return nil if count.to_i <= 0

      { key: key, count: count, message: message }
    end

    def stock_item_ids
      @stock_item_ids ||= StockItem.where(warehouse_id: @warehouse.id).pluck(:id)
    end

    def deletable_stock_item_ids
      @deletable_stock_item_ids ||= begin
        scope = StockItem
          .where(id: stock_item_ids)
          .where(quantity_on_hand: 0, quantity_reserved: 0, quantity_unavailable: 0)
          .where.not(id: StockMovement.where(stock_item_id: stock_item_ids).select(:stock_item_id))
          .where.not(id: StockReservation.where(stock_item_id: stock_item_ids).select(:stock_item_id))

        if defined?(StockCostLayer)
          scope = scope.where.not(id: StockCostLayer.where(stock_item_id: stock_item_ids).select(:stock_item_id))
        end

        scope.pluck(:id)
      end
    end

    def nonzero_stock_items_count
      StockItem.where(warehouse_id: @warehouse.id)
               .where("quantity_on_hand <> 0 OR quantity_reserved <> 0 OR quantity_unavailable <> 0")
               .count
    end

    def stock_reservations_count
      return 0 if stock_item_ids.empty?

      StockReservation.where(stock_item_id: stock_item_ids).count
    end

    def stock_movements_count
      return 0 if stock_item_ids.empty?

      StockMovement.where(stock_item_id: stock_item_ids).count
    end

    def stock_cost_layers_count
      return 0 unless defined?(StockCostLayer)
      return 0 if stock_item_ids.empty?

      StockCostLayer.where(stock_item_id: stock_item_ids).count
    end

    def purchase_orders_count
      return 0 unless defined?(PurchaseOrder)

      PurchaseOrder.where(warehouse_id: @warehouse.id).count
    end

    def production_orders_count
      return 0 unless defined?(ProductionOrder)

      ProductionOrder.where(warehouse_id: @warehouse.id).count
    end

    def stock_transfers_count
      return 0 unless defined?(StockTransfer)

      StockTransfer.where("from_warehouse_id = :id OR to_warehouse_id = :id", id: @warehouse.id).count
    end

    def showroom_reversals_count
      return 0 unless defined?(ShowroomReversal)

      ShowroomReversal.where(warehouse_id: @warehouse.id).count
    end

    def user_roles_count
      return 0 unless defined?(UserRole)

      UserRole.where(warehouse_id: @warehouse.id).count
    end
  end
end
