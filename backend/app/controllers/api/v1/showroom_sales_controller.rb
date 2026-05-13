module Api
  module V1
    class ShowroomSalesController < ApplicationController
      include Pundit::Authorization

      # POST /api/v1/showroom_sales
      def create
        authorize Order # piggyback on order policy: requires sales:write
        result = Sales::ShowroomSalesReportPoster.call(report_params.merge(actor: current_user))

        record_audit(result)

        render json: { data: serialize(result) }, status: :created
      rescue Sales::ShowroomSalesReportPoster::InvalidInput,
             Sales::ShowroomSalesReportPoster::AlreadyPosted,
             Inventory::WriteMovement::InsufficientStockError => e
        render_error(422, "invalid", e.message)
      rescue ActiveRecord::RecordNotFound => e
        render_error(404, "not_found", e.message)
      end

      private

      def report_params
        params.permit(
          :warehouse_id, :period, :report_date, :currency, :notes,
          line_items: %i[variant_id quantity unit_price]
        ).to_h
      end

      def record_audit(result)
        # Audit subject: prefer the order (if any), otherwise the reversal.
        subject = result.order || result.reversal
        return unless subject

        AuditLog.record(
          user:    current_user,
          action:  "showroom.sales_report.posted",
          subject: subject,
          diff: {
            warehouse_id:    params[:warehouse_id],
            period:          params[:period],
            sales_total:     result.sales_total.to_s,
            reversal_total:  result.reversal_total.to_s,
            order_id:        result.order_id,
            reversal_id:     result.reversal_id
          },
          request: request
        )
      end

      def serialize(result)
        order_payload    = result.order ? OrderSerializer.call(result.order) : nil
        reversal_payload =
          if result.reversal
            {
              id:               result.reversal.id,
              warehouse_id:     result.reversal.warehouse_id,
              period:           result.reversal.period,
              currency:         result.reversal.currency,
              total_amount:     result.reversal.total_amount.to_s,
              lines:            result.reversal.lines,
              idempotency_key:  result.reversal.idempotency_key,
              posted_at:        result.reversal.posted_at
            }
          end

        # Preserve the legacy shape (id/order_number/total_price) on the top
        # level when a sales order was created so existing frontend callers
        # keep working.
        base = order_payload ? order_payload.slice(:id, :order_number, :total_price) : {}
        base.merge(
          order:           order_payload,
          reversal:        reversal_payload,
          sales_total:     result.sales_total.to_s,
          reversal_total:  result.reversal_total.to_s
        )
      end
    end
  end
end
