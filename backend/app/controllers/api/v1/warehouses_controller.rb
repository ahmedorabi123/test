module Api
  module V1
    class WarehousesController < ApplicationController
      before_action :set_warehouse, only: %i[show update destroy]

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
        @warehouse.update!(warehouse_params)
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

      def warehouse_params
        params.require(:warehouse).permit(
          :name, :code, :address, :active, :kind, :partner_name,
          :partner_email, :partner_phone, :commission_rate, :currency, :notes
        )
      end
    end
  end
end
