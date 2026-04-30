module Api
  module V1
    class ShowroomSalesController < ApplicationController
      include Pundit::Authorization

      # POST /api/v1/showroom_sales
      def create
        authorize Order  # piggyback on order policy: requires sales:write
        order = Sales::ShowroomSalesReportPoster.call(report_params)
        AuditLog.record(user: current_user, action: "showroom.sales_report.posted",
                        subject: order,
                        diff: { period: params[:period], warehouse_id: params[:warehouse_id] })
        render json: { data: OrderSerializer.call(order) }, status: :created
      rescue Sales::ShowroomSalesReportPoster::InvalidInput,
             Sales::ShowroomSalesReportPoster::AlreadyPosted => e
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
    end
  end
end
