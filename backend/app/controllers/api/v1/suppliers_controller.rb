module Api
  module V1
    class SuppliersController < ApplicationController
      include Sortable
      include Exportable

      sortable_by "supplier_code", "name", "email", "status", "created_at", "updated_at",
                  default: { created_at: :desc }

      before_action :set_supplier, only: %i[show update destroy purchase_orders]

      def index
        authorize Supplier
        scope = filtered_scope

        page     = [ params[:page].to_i, 1 ].max
        per_page = (params[:per_page].to_i.positive? ? params[:per_page].to_i : 25).clamp(1, 200)
        records  = apply_sort(scope).offset((page - 1) * per_page).limit(per_page)

        render json: {
          data: records.map { |s| SupplierSerializer.call(s) },
          meta: { page: page, per_page: per_page, total: scope.count }
        }
      end

      def show
        authorize @supplier
        render json: { data: SupplierSerializer.call(@supplier, include_summary: true) }
      end

      def purchase_orders
        authorize @supplier, :show?
        records = @supplier.purchase_orders.includes(:warehouse).order(created_at: :desc)
        render json: { data: records.map { |po| PurchaseOrderSerializer.call(po, include_line_items: false) } }
      end

      def create
        authorize Supplier
        s = Supplier.new(supplier_params)
        if s.save
          render json: { data: SupplierSerializer.call(s) }, status: :created
        else
          render_error(422, "unprocessable_entity", s.errors.full_messages.join(", "))
        end
      end

      def update
        authorize @supplier
        if @supplier.update(supplier_params)
          render json: { data: SupplierSerializer.call(@supplier) }
        else
          render_error(422, "unprocessable_entity", @supplier.errors.full_messages.join(", "))
        end
      end

      def destroy
        authorize @supplier
        @supplier.update!(status: "inactive")
        head :no_content
      end

      # POST /api/v1/suppliers/bulk (deactivate)
      def bulk
        authorize Supplier
        ids = Array(params[:ids])
        action_type = params[:action_type].to_s
        scope = Supplier.where(id: ids)
        count = 0

        case action_type
        when "deactivate"
          scope.find_each { |s| s.update!(status: "inactive"); count += 1 }
        when "activate"
          scope.find_each { |s| s.update!(status: "active"); count += 1 }
        else
          return render_error(400, "bad_request", "Unsupported action: #{action_type}")
        end

        render json: { data: { action: action_type, affected: count } }
      end

      private

      def filtered_scope
        scope = policy_scope(Supplier)
        scope = scope.where(status: params[:status]) if params[:status].present?
        if params[:search].present?
          q = "%#{params[:search]}%"
          scope = scope.where(
            "supplier_code ILIKE :q OR name ILIKE :q OR email ILIKE :q OR phone ILIKE :q OR tax_id ILIKE :q",
            q: q
          )
        end
        scope
      end

      def set_supplier
        @supplier = Supplier.find(params[:id])
      end

      def supplier_params
        params.require(:supplier).permit(:supplier_code, :name, :email, :phone, :tax_id, :currency, :status,
                                         :lead_time_days, :notes,
                                         address: {}, payment_terms: {})
      end

      def export_scope
        authorize Supplier
        apply_sort(filtered_scope)
      end

      def export_columns
        {
          "Name"       => :name,
          "Email"      => :email,
          "Phone"      => :phone,
          "Tax ID"     => :tax_id,
          "Currency"   => :currency,
          "Status"     => :status,
          "Notes"      => :notes,
          "Created At" => :created_at
        }
      end
    end
  end
end
