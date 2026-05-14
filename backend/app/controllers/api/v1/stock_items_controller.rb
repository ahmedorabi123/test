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
      before_action :ensure_stock_item_mutable, only: %i[update destroy]

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
        return unless ensure_inventory_sources_mutable!(variant, warehouse)

        si = StockItem.find_or_initialize_by(variant: variant, warehouse: warehouse)
        return unless ensure_not_shopify_origin!(si)
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
          result = Catalog::VariantCostResolver.call(variant)
          if result.cost.positive?
            Inventory::RecordCostLayer.call(
              stock_item: si,
              quantity: qty,
              unit_cost: result.cost,
              source: si,
              details: { source: result.source, reason: new_record ? "initial_stock" : "manual_stock_addition" }
            )
          end
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
        adjustment_reason = params.dig(:stock_item, :adjustment_reason).presence ||
                            params[:adjustment_reason].presence ||
                            "correction"
        adjustment_note = params.dig(:stock_item, :adjustment_note).presence ||
                          params[:adjustment_note].presence

        unless Inventory::ManualAdjustment::REASONS.include?(adjustment_reason)
          return render_error(422, "invalid_adjustment_reason",
                              "adjustment_reason must be one of #{Inventory::ManualAdjustment::REASONS.join(', ')}")
        end

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
            Inventory::ManualAdjustment.call(
              stock_item:        @stock_item,
              delta:             delta,
              adjustment_reason: adjustment_reason,
              note:              adjustment_note,
              actor:             current_user
            )
            AuditLog.record(user: current_user, action: "stock_item.adjusted",
                            subject: @stock_item, request: request,
                            diff: { delta: delta, before: before, after: new_qty,
                                    reason: adjustment_reason, note: adjustment_note })
          end
        end

        render json: { data: StockItemSerializer.call(@stock_item.reload) }
      rescue Inventory::ManualAdjustment::InvalidReason => e
        render_error(422, "invalid_adjustment_reason", e.message)
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
        return unless ensure_no_shopify_origin!(scope)

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

      def ensure_stock_item_mutable
        ensure_not_shopify_origin!(@stock_item)
      end

      def ensure_inventory_sources_mutable!(variant, warehouse)
        locked = [variant, variant.product, warehouse].compact.any? do |record|
          record.respond_to?(:shopify_origin?) && record.shopify_origin?
        end
        return true unless locked

        render_read_only_shopify_resource
        false
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
