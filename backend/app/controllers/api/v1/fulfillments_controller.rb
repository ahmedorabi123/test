module Api
  module V1
    class FulfillmentsController < ApplicationController
      include Sortable
      include Exportable

      sortable_by "created_at", "updated_at", "status", "tracking_company",
          "tracking_number", "delivery_status", "shipped_at", "delivered_at",
          "order_number", "customer_name",
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
        fulfillment = Fulfillment.includes(:shipment_events, :fulfillment_line_items, order: :customer).find(params[:id])
        authorize fulfillment
        render json: { data: FulfillmentSerializer.call(fulfillment) }
      end

      def events
        fulfillment = Fulfillment.find(params[:id])
        authorize fulfillment, :show?
        render json: { data: fulfillment.shipment_events.order(created_at: :asc).map { |event| ShipmentEventSerializer.call(event) } }
      end

      def annotation
        fulfillment = Fulfillment.find(params[:id])
        authorize fulfillment, :update?
        fulfillment.update!(annotation_params)
        Shipping::RecordShipmentEvent.call(fulfillment, kind: "annotation_updated", payload: annotation_params.to_h, actor: current_user)
        render json: { data: FulfillmentSerializer.call(fulfillment.reload) }
      end

      # POST /api/v1/fulfillments/:id/transition_delivery  { to: "in_transit" | "delivered" | "failed", note: "..." }
      def transition_delivery
        fulfillment = Fulfillment.find(params[:id])
        authorize fulfillment, :transition_delivery?
        target = params[:to].to_s
        return render_error(400, "bad_request", "missing 'to'") if target.blank?

        updated = Shipping::TransitionDelivery.call(
          fulfillment,
          to:    target,
          actor: current_user,
          note:  params[:note].presence
        )
        render json: { data: FulfillmentSerializer.call(updated) }
      rescue Shipping::TransitionDelivery::InvalidTransition => e
        render_error(422, "unprocessable_entity", e.message)
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
      rescue Shipping::CreateManualFulfillment::AlreadyFulfilled => e
        render_error(422, "already_fulfilled", e.message)
      rescue ActiveRecord::RecordInvalid => e
        render_error(422, "unprocessable_entity", e.message)
      end

      # POST /api/v1/fulfillments/bulk (no-op stub; reserved for future)
      def bulk
        authorize Fulfillment, :index?
        ids = Array(params[:ids])
        tag = params.dig(:payload, :tag).to_s.strip
        return render_error(400, "bad_request", "Only add_tag is supported") unless params[:action_type].to_s == "add_tag" && tag.present?

        count = 0
        Fulfillment.where(id: ids).find_each do |fulfillment|
          fulfillment.update!(tags: (Array(fulfillment.tags) + [tag]).uniq)
          count += 1
        end
        render json: { data: { action: "add_tag", affected: count } }
      end

      private

      def filtered_scope
        scope = policy_scope(Fulfillment).includes(order: :customer)
        scope = scope.where(order_id: params[:order_id]) if params[:order_id].present?
        scope = scope.where(status:   params[:status])   if params[:status].present?
        scope = scope.where(delivery_status: params[:delivery_status]) if params[:delivery_status].present?
        scope = scope.where("fulfillments.created_at >= ?", Time.zone.parse(params[:from])) if params[:from].present?
        scope = scope.where("fulfillments.created_at <= ?", Time.zone.parse(params[:to])) if params[:to].present?
        if params[:carrier].present?
          scope = scope.where("LOWER(tracking_company) = ?", params[:carrier].to_s.downcase)
        end
        case params[:source].to_s
        when "shopify"
          scope = scope.where.not(shopify_fulfillment_id: nil)
        when "manual"
          scope = scope.where(shopify_fulfillment_id: nil)
        when "bosta"
          scope = scope.where("LOWER(tracking_company) = ? OR service = ?", "bosta", "bosta")
        end
        if params[:search].present?
          q = "%#{params[:search]}%"
          scope = scope.left_joins(:order).where(
            "fulfillments.tracking_number ILIKE :q OR fulfillments.tracking_company ILIKE :q OR orders.order_number ILIKE :q OR orders.external_number ILIKE :q OR orders.customer_email ILIKE :q OR orders.customer_name ILIKE :q",
            q: q
          )
        end
        scope
      end

      def apply_sort(scope)
        dir = params[:dir].to_s.downcase == "desc" ? "DESC" : "ASC"
        case params[:sort].to_s
        when "order_number"
          scope.left_joins(:order).order(Arel.sql("orders.order_number #{dir} NULLS LAST, fulfillments.id #{dir}"))
        when "customer_name"
          scope.left_joins(:order).order(Arel.sql("orders.customer_name #{dir} NULLS LAST, fulfillments.id #{dir}"))
        else
          super
        end
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

      def annotation_params
        params.require(:fulfillment).permit(:notes, tags: [])
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
