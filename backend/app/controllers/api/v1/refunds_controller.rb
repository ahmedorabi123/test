module Api
  module V1
    class RefundsController < ApplicationController
      include Sortable
      include Exportable

      sortable_by "created_at", "processed_at", "amount", "reason", "status", "kind",
          "order_number", "customer_name",
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
        refund = Refund.includes(:refund_line_items, order: :customer).find(params[:id])
        authorize refund
        render json: { data: RefundSerializer.call(refund) }
      end

      # POST /api/v1/refunds — manual (Estebdal / showroom) refund.
      def create
        authorize Refund
        refund = Sales::ManualRefundCreator.call(refund_params.merge(idempotency_key: request.headers["Idempotency-Key"].presence))
        AuditLog.record(user: current_user, action: "refund.manual_create",
                        subject: refund, diff: { amount: refund.amount.to_s })
        status = refund.previous_changes.empty? ? :ok : :created
        render json: { data: RefundSerializer.call(refund), meta: { duplicate: status == :ok } }, status: status
      rescue Sales::ManualRefundCreator::InvalidInput, ActiveRecord::RecordNotFound => e
        render_error(422, "invalid", e.message)
      rescue ActiveRecord::RecordInvalid => e
        render_error(422, "invalid", e.record.errors.full_messages.join(", "))
      end

      def bulk
        authorize Refund, :index?
        render_error(400, "bad_request", "No bulk actions supported for refunds")
      end

      def transition
        refund = Refund.find(params[:id])
        authorize refund, :update?
        return unless ensure_not_shopify_origin!(refund)
        updated = Sales::RefundStateMachine.call(refund, to: params[:to], actor: current_user)
        render json: { data: RefundSerializer.call(updated) }
      rescue Sales::RefundStateMachine::InvalidTransition => e
        render_error(422, "unprocessable_entity", e.message)
      end

      def cancel
        refund = Refund.find(params[:id])
        authorize refund, :update?
        return unless ensure_not_shopify_origin!(refund)
        updated = Sales::RefundStateMachine.call(refund, to: "cancelled", actor: current_user)
        render json: { data: RefundSerializer.call(updated) }
      rescue Sales::RefundStateMachine::InvalidTransition => e
        render_error(422, "unprocessable_entity", e.message)
      end

      private

      def refund_params
        params.require(:refund).permit(
          :order_id, :amount, :currency, :reason, :note, :restock, :restock_warehouse_id,
          :status, :kind,
          line_items: %i[order_line_item_id quantity subtotal]
        ).to_h
      end

      def filtered_scope
        scope = policy_scope(Refund).includes(order: :customer)
        scope = scope.where(order_id: params[:order_id]) if params[:order_id].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.where(kind: params[:kind]) if params[:kind].present?
        scope = scope.where(reason: params[:reason]) if params[:reason].present?
        scope = scope.where(restock: ActiveModel::Type::Boolean.new.cast(params[:restock])) if params.key?(:restock)
        scope = scope.where("refunds.created_at >= ?", Time.zone.parse(params[:from])) if params[:from].present?
        scope = scope.where("refunds.created_at <= ?", Time.zone.parse(params[:to])) if params[:to].present?
        case params[:source].to_s
        when "shopify"
          scope = scope.where.not(shopify_refund_id: nil)
        when "manual"
          scope = scope.where(shopify_refund_id: nil)
        when "estebdal"
          scope = scope.where(kind: "estebdal")
        end
        if params[:search].present?
          q = "%#{params[:search]}%"
          scope = scope.left_joins(:order).where(
            "orders.order_number ILIKE :q OR orders.customer_email ILIKE :q OR orders.customer_name ILIKE :q OR refunds.reason ILIKE :q OR refunds.note ILIKE :q",
            q: q
          )
        end
        scope
      end

      def apply_sort(scope)
        dir = params[:dir].to_s.downcase == "desc" ? "DESC" : "ASC"
        case params[:sort].to_s
        when "order_number"
          scope.left_joins(:order).order(Arel.sql("orders.order_number #{dir} NULLS LAST, refunds.id #{dir}"))
        when "customer_name"
          scope.left_joins(:order).order(Arel.sql("orders.customer_name #{dir} NULLS LAST, refunds.id #{dir}"))
        else
          super
        end
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
          "Status"     => :status,
          "Kind"       => :kind,
          "Note"       => :note,
          "Created At" => :created_at
        }
      end
    end
  end
end
