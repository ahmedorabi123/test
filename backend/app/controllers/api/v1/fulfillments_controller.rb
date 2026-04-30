module Api
  module V1
    class FulfillmentsController < ApplicationController
      include Sortable
      include Exportable

      sortable_by "created_at", "updated_at", "status", "tracking_company",
                  default: { created_at: :desc }

      # GET /api/v1/fulfillments?order_id=&carrier=&status=&page=&per_page=&sort=&dir=
      def index
        authorize Fulfillment
        scope = filtered_scope

        page     = [params[:page].to_i, 1].max
        per_page = params[:per_page].to_i
        per_page = 25  if per_page <= 0
        per_page = 200 if per_page > 200

        records = apply_sort(scope).offset((page - 1) * per_page).limit(per_page)
        total   = scope.count

        render json: {
          data: records.map { |f| FulfillmentSerializer.call(f, include_line_items: false) },
          meta: { page: page, per_page: per_page, total: total }
        }
      end

      def show
        fulfillment = Fulfillment.find(params[:id])
        authorize fulfillment
        render json: { data: FulfillmentSerializer.call(fulfillment) }
      end

      # POST /api/v1/fulfillments
      # Creates a manual fulfillment (non-Shopify) for an ERP-only order.
      # Body: { fulfillment: { order_id:, tracking_company:, tracking_number:,
      #                        tracking_url:, service:, shipped_at:,
      #                        transition_order:, line_items: [{order_line_item_id:, quantity:}] } }
      def create
        authorize Fulfillment
        attrs = create_params
        order = Order.find(attrs.fetch(:order_id))

        fulfillment = Shipping::CreateManualFulfillment.call(
          order:            order,
          tracking_company: attrs[:tracking_company],
          tracking_number:  attrs[:tracking_number],
          tracking_url:     attrs[:tracking_url],
          service:          attrs[:service],
          shipped_at:       parse_time(attrs[:shipped_at]),
          line_items:       Array(attrs[:line_items]),
          transition_order: attrs.fetch(:transition_order, true),
          actor:            current_user
        )
        render json: { data: FulfillmentSerializer.call(fulfillment) }, status: :created
      rescue Shipping::CreateManualFulfillment::InvalidInput => e
        render_error(422, "unprocessable_entity", e.message)
      rescue ActiveRecord::RecordInvalid => e
        render_error(422, "unprocessable_entity", e.message)
      end

      # POST /api/v1/fulfillments/bulk (no-op stub; reserved for future)
      def bulk
        authorize Fulfillment, :index?
        render_error(400, "bad_request", "No bulk actions supported for fulfillments")
      end

      private

      def filtered_scope
        scope = policy_scope(Fulfillment).includes(:order)
        scope = scope.where(order_id: params[:order_id]) if params[:order_id].present?
        scope = scope.where(status:   params[:status])   if params[:status].present?
        if params[:carrier].present?
          scope = scope.where("LOWER(tracking_company) = ?", params[:carrier].to_s.downcase)
        end
        scope
      end

      def export_scope
        authorize Fulfillment
        apply_sort(filtered_scope)
      end

      def export_columns
        {
          "Order #"          => ->(f) { f.order&.order_number },
          "Status"           => :status,
          "Tracking Number"  => :tracking_number,
          "Tracking Company" => :tracking_company,
          "Tracking URL"     => :tracking_url,
          "Shipped At"       => :shipped_at,
          "Delivered At"     => :delivered_at,
          "Created At"       => :created_at
        }
      end

      def create_params
        params.require(:fulfillment).permit(
          :order_id, :tracking_company, :tracking_number, :tracking_url,
          :service, :shipped_at, :transition_order,
          line_items: %i[order_line_item_id quantity]
        ).to_h.with_indifferent_access
      end

      def parse_time(value)
        return nil if value.blank?
        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
