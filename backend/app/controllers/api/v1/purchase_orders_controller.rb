module Api
  module V1
    class PurchaseOrdersController < ApplicationController
      include Sortable
      include Exportable

      sortable_by "po_number", "status", "expected_at", "created_at", "updated_at",
                  default: { created_at: :desc }

      before_action :set_po, only: %i[show update receive cancel]

      def index
        authorize PurchaseOrder
        scope = filtered_scope

        page     = [params[:page].to_i, 1].max
        per_page = (params[:per_page].to_i.positive? ? params[:per_page].to_i : 25).clamp(1, 200)
        records  = apply_sort(scope).offset((page - 1) * per_page).limit(per_page)

        render json: {
          data: records.map { |po| PurchaseOrderSerializer.call(po, include_line_items: false) },
          meta: { page: page, per_page: per_page, total: scope.count }
        }
      end

      def show
        authorize @po
        render json: { data: PurchaseOrderSerializer.call(@po) }
      end

      def create
        authorize PurchaseOrder
        po = Purchases::PurchaseOrderCreator.call(po_params.merge(created_by_id: current_user.id))
        render json: { data: PurchaseOrderSerializer.call(po) }, status: :created
      rescue Purchases::PurchaseOrderCreator::InvalidInput, ActiveRecord::RecordNotFound => e
        render_error(422, "unprocessable_entity", e.message)
      end

      def update
        authorize @po
        attrs = po_update_params.to_h
        if attrs[:status] == "ordered" && @po.status == "draft"
          attrs[:ordered_at] ||= Time.current
        end
        if @po.update(attrs)
          render json: { data: PurchaseOrderSerializer.call(@po) }
        else
          render_error(422, "unprocessable_entity", @po.errors.full_messages.join(", "))
        end
      end

      # POST /api/v1/purchase_orders/:id/receive
      # payload: { receipts: [{line_item_id:, quantity:}], warehouse_id: <optional> }
      def receive
        authorize @po, :receive?
        warehouse = params[:warehouse_id].present? ? Warehouse.find(params[:warehouse_id]) : @po.warehouse
        po = Purchases::ReceiveService.call(purchase_order: @po,
                                            receipts: params[:receipts] || [],
                                            warehouse: warehouse)
        render json: { data: PurchaseOrderSerializer.call(po) }
      rescue Purchases::ReceiveService::InvalidInput,
             Purchases::ReceiveService::MissingWarehouse,
             Inventory::WriteMovement::InsufficientStockError => e
        render_error(422, "unprocessable_entity", e.message)
      end

      # POST /api/v1/purchase_orders/:id/cancel
      def cancel
        authorize @po, :update?
        @po.update!(status: "cancelled")
        render json: { data: PurchaseOrderSerializer.call(@po) }
      end

      # POST /api/v1/purchase_orders/bulk
      def bulk
        authorize PurchaseOrder
        ids = Array(params[:ids])
        action_type = params[:action_type].to_s
        scope = PurchaseOrder.where(id: ids)
        count = 0

        case action_type
        when "cancel"
          scope.where.not(status: %w[cancelled received]).find_each do |po|
            po.update!(status: "cancelled")
            count += 1
          end
        else
          return render_error(400, "bad_request", "Unsupported action: #{action_type}")
        end

        render json: { data: { action: action_type, affected: count } }
      end

      private

      def filtered_scope
        scope = policy_scope(PurchaseOrder).includes(:supplier, :warehouse)
        scope = scope.where(status: params[:status])           if params[:status].present?
        scope = scope.where(supplier_id: params[:supplier_id]) if params[:supplier_id].present?
        if params[:search].present?
          q = "%#{params[:search]}%"
          scope = scope.joins(:supplier).where("purchase_orders.po_number ILIKE :q OR suppliers.name ILIKE :q", q: q)
        end
        scope
      end

      def set_po
        @po = PurchaseOrder.find(params[:id])
      end

      def po_params
        params.require(:purchase_order).permit(
          :supplier_id, :warehouse_id, :currency, :expected_at,
          :total_tax, :total_shipping, :notes,
          line_items: %i[variant_id sku title quantity_ordered unit_cost]
        )
      end

      def po_update_params
        params.require(:purchase_order).permit(:status, :expected_at, :notes, :warehouse_id)
      end

      def export_scope
        authorize PurchaseOrder
        apply_sort(filtered_scope)
      end

      def export_columns
        {
          "PO #"        => :po_number,
          "Supplier"    => ->(po) { po.supplier&.name },
          "Warehouse"   => ->(po) { po.warehouse&.name },
          "Status"      => :status,
          "Currency"    => :currency,
          "Total"       => :total_amount,
          "Expected At" => :expected_at,
          "Created At"  => :created_at
        }
      end
    end
  end
end
