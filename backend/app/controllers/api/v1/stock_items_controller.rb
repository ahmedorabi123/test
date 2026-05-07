module Api
  module V1
    class StockItemsController < ApplicationController
      include Sortable
      include Exportable

      sortable_by "quantity_on_hand", "quantity_reserved", "quantity_unavailable",
                  "low_stock_threshold", "updated_at", "created_at",
                  "product_title", "variant_sku", "warehouse_name", "available",
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

      def apply_sort(scope)
        dir = params[:dir].to_s.downcase == "desc" ? "DESC" : "ASC"

        case params[:sort].to_s
        when "product_title"
          scope.left_joins(variant: :product)
               .order(Arel.sql("products.title #{dir} NULLS LAST, variants.title #{dir} NULLS LAST, stock_items.id #{dir}"))
        when "variant_sku"
          scope.left_joins(:variant)
               .order(Arel.sql("variants.sku #{dir} NULLS LAST, variants.title #{dir} NULLS LAST, stock_items.id #{dir}"))
        when "warehouse_name"
          scope.left_joins(:warehouse)
               .order(Arel.sql("warehouses.name #{dir} NULLS LAST, stock_items.id #{dir}"))
        when "available"
          scope.order(Arel.sql("(stock_items.quantity_on_hand - stock_items.quantity_reserved - stock_items.quantity_unavailable) #{dir}, stock_items.id #{dir}"))
        else
          super
        end
      end

      # POST /api/v1/stock_items — initial stock creation.
      def create
        authorize StockItem
        variant   = Variant.find(params.require(:variant_id))
        warehouse = Warehouse.find(params.require(:warehouse_id))
        qty       = Integer(params[:quantity_on_hand].presence || 0)
        threshold = Integer(params[:low_stock_threshold].presence || 0)

        si = StockItem.find_or_initialize_by(variant: variant, warehouse: warehouse)
        new_record = si.new_record?
        si.quantity_on_hand ||= 0
        si.low_stock_threshold = threshold
        si.save!

        if qty > 0
          Inventory::WriteMovement.call(
            stock_item: si,
            delta:      qty,
            reason:     new_record ? "initial_stock" : "adjusted",
            note:       new_record ? "Initial stock" : "Manual stock addition"
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
        before_unavailable = @stock_item.quantity_unavailable
        before_reason = @stock_item.unavailability_reason

        if attrs[:low_stock_threshold].present?
          @stock_item.update!(low_stock_threshold: Integer(attrs[:low_stock_threshold]))
        end

        if attrs.key?(:quantity_unavailable)
          @stock_item.update!(
            quantity_unavailable:  Integer(attrs[:quantity_unavailable]),
            unavailability_reason: attrs[:unavailability_reason].presence
          )

          if @stock_item.quantity_unavailable != before_unavailable || @stock_item.unavailability_reason != before_reason
            Inventory::WriteMovement.call(
              stock_item: @stock_item,
              delta: 0,
              reason: "adjusted",
              note: "Unavailable changed from #{before_unavailable} to #{@stock_item.quantity_unavailable}: #{@stock_item.unavailability_reason.presence || 'no reason'}"
            )
          end
        end

        if attrs[:quantity_on_hand].present?
          new_qty = Integer(attrs[:quantity_on_hand])
          delta   = new_qty - before
          if delta != 0
            Inventory::WriteMovement.call(
              stock_item: @stock_item,
              delta:      delta,
              reason:     "adjusted",
              note:       "Manual on-hand adjustment"
            )
          end
        end

        render json: { data: StockItemSerializer.call(@stock_item.reload) }
      end

      def destroy
        authorize @stock_item
        @stock_item.destroy!
        head :no_content
      rescue ActiveRecord::RecordNotDestroyed, ActiveRecord::DeleteRestrictionError => e
        render json: { error: { status: 400, detail: e.message } }, status: :bad_request
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
        scope = policy_scope(StockItem).includes(:warehouse, variant: :product)
        if params[:search].present?
          q = "%#{params[:search]}%"
          scope = scope.joins(variant: :product)
                       .where("variants.sku ILIKE :q OR products.title ILIKE :q OR variants.title ILIKE :q", q: q)
        end
        scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
        scope = scope.where(variant_id: params[:variant_id])     if params[:variant_id].present?
        scope = scope.low_stock                                   if params[:low_stock] == "true"
        scope = scope.where("stock_items.quantity_unavailable > 0") if params[:has_unavailable] == "true"
        scope
      end

      def set_stock_item
        @stock_item = StockItem.find(params[:id])
      end

      def stock_item_params
        params.require(:stock_item).permit(:quantity_on_hand, :low_stock_threshold,
                                           :quantity_unavailable, :unavailability_reason)
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
          "Reserved"      => :quantity_reserved,
          "Unavailable"   => :quantity_unavailable,
          "Available"     => ->(si) { si.available },
          "Low Threshold" => :low_stock_threshold,
          "Updated At"    => :updated_at
        }
      end
    end
  end
end
