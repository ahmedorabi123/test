module Api
  module V1
    class StockItemsController < ApplicationController
      include Sortable
      include Exportable

      sortable_by "quantity_on_hand", "low_stock_threshold", "updated_at", "created_at",
                  default: { updated_at: :desc }

      before_action :set_stock_item, only: %i[show update destroy]

      # GET /api/v1/stock_items?warehouse_id=&variant_id=&low_stock=true&sort=&dir=&page=&per_page=
      def index
        authorize StockItem
        scope = filtered_scope

        page     = [params[:page].to_i, 1].max
        per_page = params[:per_page].to_i
        per_page = 50  if per_page <= 0
        per_page = 200 if per_page > 200

        records = apply_sort(scope).offset((page - 1) * per_page).limit(per_page)
        total   = scope.count

        render json: {
          data: records.map { |si| StockItemSerializer.call(si) },
          meta: { page: page, per_page: per_page, total: total }
        }
      end

      def show
        authorize @stock_item
        render json: { data: StockItemSerializer.call(@stock_item) }
      end

      # POST /api/v1/stock_items — initial stock creation.
      def create
        authorize StockItem
        variant   = Variant.find(params.require(:variant_id))
        warehouse = Warehouse.find(params.require(:warehouse_id))
        qty       = Integer(params[:quantity_on_hand].presence || 0)
        threshold = Integer(params[:low_stock_threshold].presence || 0)

        si = StockItem.find_or_initialize_by(variant: variant, warehouse: warehouse)
        if si.persisted?
          return render_error(422, "unprocessable_entity", "Stock item already exists for this variant and warehouse")
        end
        si.quantity_on_hand    = 0
        si.low_stock_threshold = threshold
        si.save!

        if qty > 0
          Inventory::WriteMovement.call(
            stock_item: si,
            delta:      qty,
            reason:     "initial_stock"
          )
        end

        render json: { data: StockItemSerializer.call(si.reload) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_error(422, "unprocessable_entity", e.message)
      end

      # PATCH /api/v1/stock_items/:id — manual adjustment via movement.
      def update
        authorize @stock_item
        attrs  = stock_item_params
        before = @stock_item.quantity_on_hand

        if attrs[:low_stock_threshold].present?
          @stock_item.update!(low_stock_threshold: Integer(attrs[:low_stock_threshold]))
        end

        if attrs[:quantity_on_hand].present?
          new_qty = Integer(attrs[:quantity_on_hand])
          delta   = new_qty - before
          if delta != 0
            Inventory::WriteMovement.call(
              stock_item: @stock_item,
              delta:      delta,
              reason:     "adjusted"
            )
          end
        end

        render json: { data: StockItemSerializer.call(@stock_item.reload) }
      end

      def destroy
        authorize @stock_item
        @stock_item.destroy!
        head :no_content
      end

      # POST /api/v1/stock_items/bulk  (set_threshold/delete)
      def bulk
        authorize StockItem
        ids = Array(params[:ids])
        action_type = params[:action_type].to_s
        scope = StockItem.where(id: ids)
        count = 0

        case action_type
        when "set_threshold"
          threshold = Integer(params.dig(:payload, :threshold))
          scope.find_each { |si| si.update!(low_stock_threshold: threshold); count += 1 }
        when "delete"
          scope.find_each { |si| si.destroy!; count += 1 }
        else
          return render_error(400, "bad_request", "Unsupported action: #{action_type}")
        end

        render json: { data: { action: action_type, affected: count } }
      end

      private

      def filtered_scope
        scope = policy_scope(StockItem).includes(:variant, :warehouse)
        scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
        scope = scope.where(variant_id: params[:variant_id])     if params[:variant_id].present?
        scope = scope.low_stock                                   if params[:low_stock] == "true"
        scope
      end

      def set_stock_item
        @stock_item = StockItem.find(params[:id])
      end

      def stock_item_params
        params.require(:stock_item).permit(:quantity_on_hand, :low_stock_threshold)
      end

      def export_scope
        authorize StockItem
        apply_sort(filtered_scope)
      end

      def export_columns
        {
          "SKU"           => ->(si) { si.variant&.sku },
          "Variant"       => ->(si) { si.variant&.title },
          "Product"       => ->(si) { si.variant&.product&.title },
          "Warehouse"     => ->(si) { si.warehouse&.name },
          "On Hand"       => :quantity_on_hand,
          "Committed"     => :quantity_committed,
          "Available"     => ->(si) { si.quantity_on_hand.to_i - si.quantity_committed.to_i },
          "Low Threshold" => :low_stock_threshold,
          "Updated At"    => :updated_at
        }
      end
    end
  end
end
module Api
  module V1
    class StockItemsController < ApplicationController
      before_action :set_stock_item, only: %i[show update]

      # GET /api/v1/stock_items?warehouse_id=&variant_id=&low_stock=true
      def index
        authorize StockItem
        scope = policy_scope(StockItem).includes(:variant, :warehouse)
        scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
        scope = scope.where(variant_id: params[:variant_id])     if params[:variant_id].present?
        scope = scope.low_stock                                   if params[:low_stock] == "true"

        render json: { data: scope.map { |si| StockItemSerializer.call(si) } }
      end

      # GET /api/v1/stock_items/:id
      def show
        authorize @stock_item
        render json: { data: StockItemSerializer.call(@stock_item) }
      end

      # PATCH /api/v1/stock_items/:id (manual adjustment)
      def update
        authorize @stock_item
        before = @stock_item.quantity_on_hand
        @stock_item.update!(quantity_on_hand: Integer(stock_item_params[:quantity_on_hand]))
        delta = @stock_item.quantity_on_hand - before

        if delta != 0
          StockMovement.create!(
            stock_item:      @stock_item,
            delta:           delta,
            reason:          "adjusted",
            snapshot_before: before,
            snapshot_after:  @stock_item.quantity_on_hand
          )
        end

        render json: { data: StockItemSerializer.call(@stock_item) }
      end

      private

      def set_stock_item
        @stock_item = StockItem.find(params[:id])
      end

      def stock_item_params
        params.require(:stock_item).permit(:quantity_on_hand, :low_stock_threshold)
      end
    end
  end
end
