module Api
  module V1
    class WarehousesController < ApplicationController
      before_action :set_warehouse, only: %i[show update destroy]
      before_action :ensure_warehouse_mutable, only: %i[update destroy]

      # GET /api/v1/warehouses
      def index
        authorize Warehouse
        warehouses = policy_scope(Warehouse).order(:code)
        render json: { data: warehouses.map { |w| WarehouseSerializer.call(w) } }
      end

      # GET /api/v1/warehouses/:id
      def show
        authorize @warehouse
        render json: { data: WarehouseSerializer.call(@warehouse, include_stock: true) }
      end

      # POST /api/v1/warehouses
      def create
        authorize Warehouse
        warehouse = Warehouse.create!(warehouse_params)
        render json: { data: WarehouseSerializer.call(warehouse) }, status: :created
      end

      # PATCH /api/v1/warehouses/:id
      def update
        authorize @warehouse
        previous_commission = @warehouse.commission_rate
        @warehouse.update!(warehouse_params)
        record_commission_audit(previous_commission)
        render json: { data: WarehouseSerializer.call(@warehouse) }
      end

      # DELETE /api/v1/warehouses/:id
      def destroy
        authorize @warehouse
        @warehouse.destroy!
        head :no_content
      end

      private

      def set_warehouse
        @warehouse = Warehouse.find(params[:id])
      end

      def ensure_warehouse_mutable
        ensure_not_shopify_origin!(@warehouse)
      end

      def warehouse_params
        params.require(:warehouse).permit(
          :name, :code, :address, :active, :kind, :partner_name,
          :partner_email, :partner_phone, :commission_rate, :currency, :notes
        )
      end

      # Phase 1: commission_rate is informational only. Settlement accounting
      # comes in a later phase. Any change is recorded in the audit log so
      # finance has a trail.
      def record_commission_audit(previous)
        current = @warehouse.commission_rate
        return if previous.to_s == current.to_s

        AuditLog.record(
          user:    current_user,
          action:  "showroom.commission_rate.changed",
          subject: @warehouse,
          diff:    { from: previous&.to_s, to: current&.to_s },
          request: request
        )
      end
    end
  end
end
