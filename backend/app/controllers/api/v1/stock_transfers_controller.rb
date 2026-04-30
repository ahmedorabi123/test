module Api
  module V1
    class StockTransfersController < ApplicationController
      include Pundit::Authorization

      # POST /api/v1/stock_transfers
      def create
        authorize StockItem  # piggyback: requires inventory:write
        variant   = Variant.find(params[:variant_id])
        from_w    = Warehouse.find(params[:from_warehouse_id])
        to_w      = Warehouse.find(params[:to_warehouse_id])
        from_si, to_si = Inventory::TransferStock.call(
          variant:        variant,
          from_warehouse: from_w,
          to_warehouse:   to_w,
          quantity:       params[:quantity].to_i,
          reason:         (params[:reason].presence || "transfer")
        )
        AuditLog.record(user: current_user, action: "inventory.transfer",
                        subject: variant,
                        diff: { from: from_w.code, to: to_w.code, quantity: params[:quantity] })
        render json: {
          data: {
            from: { warehouse_code: from_w.code, on_hand: from_si.quantity_on_hand },
            to:   { warehouse_code: to_w.code,   on_hand: to_si.quantity_on_hand }
          }
        }, status: :created
      rescue Inventory::TransferStock::InsufficientStock, ArgumentError => e
        render_error(422, "invalid", e.message)
      rescue ActiveRecord::RecordNotFound => e
        render_error(404, "not_found", e.message)
      end
    end
  end
end
