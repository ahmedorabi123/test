module Api
  module V1
    class RefundsController < ApplicationController
      include Sortable
      include Exportable

      sortable_by "created_at", "amount", "reason",
                  default: { created_at: :desc }

      # GET /api/v1/refunds?order_id=&page=&per_page=&sort=&dir=
      def index
        authorize Refund
        scope = filtered_scope

        page     = [params[:page].to_i, 1].max
        per_page = params[:per_page].to_i
        per_page = 25  if per_page <= 0
        per_page = 200 if per_page > 200

        records = apply_sort(scope).offset((page - 1) * per_page).limit(per_page)
        total   = scope.count

        render json: {
          data: records.map { |r| RefundSerializer.call(r, include_line_items: false) },
          meta: { page: page, per_page: per_page, total: total }
        }
      end

      def show
        refund = Refund.find(params[:id])
        authorize refund
        render json: { data: RefundSerializer.call(refund) }
      end

      # POST /api/v1/refunds — manual (Estebdal / showroom) refund.
      def create
        authorize Refund
        refund = Sales::ManualRefundCreator.call(refund_params)
        AuditLog.record(user: current_user, action: "refund.manual_create",
                        subject: refund, diff: { amount: refund.amount.to_s })
        render json: { data: RefundSerializer.call(refund) }, status: :created
      rescue Sales::ManualRefundCreator::InvalidInput, ActiveRecord::RecordNotFound => e
        render_error(422, "invalid", e.message)
      rescue ActiveRecord::RecordInvalid => e
        render_error(422, "invalid", e.record.errors.full_messages.join(", "))
      end

      def bulk
        authorize Refund, :index?
        render_error(400, "bad_request", "No bulk actions supported for refunds")
      end

      private

      def refund_params
        params.require(:refund).permit(
          :order_id, :amount, :currency, :reason, :note, :restock, :restock_warehouse_id,
          line_items: %i[order_line_item_id quantity subtotal]
        ).to_h
      end

      def filtered_scope
        scope = policy_scope(Refund).includes(:order)
        scope = scope.where(order_id: params[:order_id]) if params[:order_id].present?
        scope
      end

      def export_scope
        authorize Refund
        apply_sort(filtered_scope)
      end

      def export_columns
        {
          "Order #"    => ->(r) { r.order&.order_number },
          "Amount"     => :amount,
          "Currency"   => :currency,
          "Reason"     => :reason,
          "Note"       => :note,
          "Created At" => :created_at
        }
      end
    end
  end
end
