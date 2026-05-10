module Api
  module V1
    class OrdersController < ApplicationController
      include Sortable
      include Exportable
      include Importable

      sortable_by "placed_at", "total_price", "order_number", "customer_email",
                  "customer_name", "status", "financial_status", "fulfillment_status",
                  "delivery_status", "last_delivery_status",
                  "created_at", "updated_at", "items_count", "total_refunded",
                  default: { placed_at: :desc }

      before_action :set_order, only: %i[show transition stock_allocation timeline]

      def importer_class
        params[:mode] == "showroom" ? Imports::ShowroomSalesImporter : Imports::OrdersImporter
      end
      private :importer_class

      # GET /api/v1/orders
      # Filters: search (order_number/external_number/customer_email), status,
      # financial_status, source, from (date), to (date), page, per_page, sort, dir
      def index
        authorize Order
        scope = filtered_scope

        page     = [ params[:page].to_i, 1 ].max
        per_page = params[:per_page].to_i
        per_page = 25  if per_page <= 0
        per_page = 200 if per_page > 200

        records = apply_sort(scope).offset((page - 1) * per_page).limit(per_page)
        total   = scope.count

        summary = {
          total_count: total,
          total_value: scope.sum(:total_price)
        }

        render json: {
          data: records.map { |o| OrderSerializer.call(o, include_line_items: false) },
          meta: { page: page, per_page: per_page, total: total, summary: summary }
        }
      end

      # GET /api/v1/orders/:id
      def show
        authorize @order
        render json: { data: OrderSerializer.call(@order) }
      end

      # POST /api/v1/orders
      # Creates a manual or showroom order. See Sales::ManualOrderCreator.
      def create
        authorize Order
        order = Sales::ManualOrderCreator.call(order_params)
        render json: { data: OrderSerializer.call(order) }, status: :created
      rescue Sales::ManualOrderCreator::InvalidInput => e
        render_error(422, "unprocessable_entity", e.message)
      rescue Inventory::Oversold => e
        render json: { error: { type: "oversold", detail: e.message, shortages: e.shortages } }, status: :unprocessable_entity
      end

      def preview_warehouse
        authorize Order, :create?
        variant_ids = Array(params[:variant_ids]).reject(&:blank?)
        warehouse = preview_best_warehouse(variant_ids)
        availability = availability_for(variant_ids)

        render json: {
          data: {
            warehouse: warehouse ? WarehouseSerializer.call(warehouse) : nil,
            availability: availability
          }
        }
      end

      def stock_allocation
        authorize @order, :show?
        render json: { data: OrderSerializer.stock_allocation(@order) }
      end

      # GET /api/v1/orders/:id/timeline
      # Returns a unified, chronologically-sorted activity feed for one order:
      # domain events on the Order aggregate, fulfillment lifecycle, shipment
      # events, and refunds. Read-only and lightweight; no pagination yet.
      def timeline
        authorize @order, :show?
        render json: { data: build_timeline(@order) }
      end

      # GET /api/v1/orders/stats?window=30
      def stats
        authorize Order, :index?
        window = (params[:window].presence || 30).to_i
        window = 30 if window <= 0 || window > 365
        scope  = Order.where("placed_at >= ?", window.days.ago)

        render json: {
          data: {
            window_days:   window,
            count:         scope.count,
            total_revenue: scope.where.not(status: "cancelled").sum(:total_price),
            by_status:     scope.group(:status).count,
            pending_count: scope.where(status: "pending").count
          }
        }
      end

      # POST /api/v1/orders/bulk  (cancel/tag — no deletion)
      def bulk
        authorize Order, :index?
        ids = Array(params[:ids])
        action_type = params[:action_type].to_s
        scope = Order.where(id: ids)
        count = 0

        case action_type
        when "cancel"
          scope.where.not(status: "cancelled").find_each do |o|
            o.update!(status: "cancelled", cancelled_at: Time.current)
            count += 1
          end
        else
          return render_error(400, "bad_request", "Unsupported action: #{action_type}")
        end

        render json: { data: { action: action_type, affected: count } }
      end

      # POST /api/v1/orders/:id/transition  { to: "paid" | "fulfilled" | "cancelled" | ... }
      def transition
        authorize @order
        target = params[:to].to_s
        return render_error(400, "bad_request", "missing 'to'") if target.blank?

        order = Sales::OrderStateMachine.call(@order, to: target, actor: current_user)
        render json: { data: OrderSerializer.call(order) }
      rescue Sales::OrderStateMachine::InvalidTransition => e
        render_error(422, "unprocessable_entity", e.message)
      end

      private

      def set_order
        @order = Order.find(params[:id])
      end

      # Builds a single chronological feed for an order from heterogeneous
      # sources. Each entry is a plain hash so the frontend can render
      # without per-source branches.
      def build_timeline(order)
        entries = []

        DomainEvent.where(aggregate_type: "Order", aggregate_id: order.id)
                   .order(occurred_at: :asc)
                   .each do |de|
          entries << {
            kind:       "event",
            type:       de.event_type,
            occurred_at: de.occurred_at,
            payload:    de.payload || {}
          }
        end

        order.fulfillments.order(created_at: :asc).each do |f|
          entries << {
            kind:       "fulfillment_created",
            type:       "fulfillment.created",
            occurred_at: f.created_at,
            payload: {
              fulfillment_id:  f.id,
              status:          f.status,
              delivery_status: f.delivery_status,
              tracking_company: f.tracking_company,
              tracking_number: f.tracking_number
            }
          }
          if f.delivered_at.present?
            entries << {
              kind:       "fulfillment_delivered",
              type:       "fulfillment.delivered",
              occurred_at: f.delivered_at,
              payload:    { fulfillment_id: f.id }
            }
          end
          f.shipment_events.order(created_at: :asc).each do |ev|
            entries << {
              kind:       "shipment_event",
              type:       "shipment.#{ev.kind}",
              occurred_at: ev.created_at,
              payload:    { fulfillment_id: f.id, kind: ev.kind, payload: ev.payload }
            }
          end
        end

        order.refunds.order(created_at: :asc).each do |r|
          entries << {
            kind:       "refund",
            type:       "refund.#{r.status}",
            occurred_at: r.processed_at || r.created_at,
            payload: {
              refund_id: r.id,
              amount:    r.amount.to_s,
              currency:  r.currency,
              status:    r.status,
              reason:    r.reason
            }
          }
        end

        entries.sort_by { |e| e[:occurred_at] || Time.at(0) }
      end

      def filtered_scope
        scope = policy_scope(Order)

        if params[:search].present?
          q = "%#{params[:search]}%"
          scope = scope.where(
            "order_number ILIKE :q OR external_number ILIKE :q OR customer_email ILIKE :q OR customer_name ILIKE :q",
            q: q
          )
        end

        scope = scope.where(status:           params[:status])           if params[:status].present?
        scope = scope.where(financial_status: params[:financial_status]) if params[:financial_status].present?
        scope = scope.where(source:           params[:source])           if params[:source].present?
        scope = scope.where(last_delivery_status: params[:delivery_status]) if params[:delivery_status].present?
        scope = scope.where("placed_at >= ?", Time.zone.parse(params[:from])) if params[:from].present?
        scope = scope.where("placed_at <= ?", Time.zone.parse(params[:to]))   if params[:to].present?
        scope
      end

      def order_params
        params.require(:order).permit(
          :source, :currency, :customer_id, :customer_email, :customer_name,
          :notes, :total_shipping, :mark_paid, :location_id, :warehouse_id,
          shipping_address: {},
          billing_address:  {},
          line_items: [
            :variant_id, :sku, :title, :variant_title,
            :quantity, :price, :total_tax, :total_discount
          ]
        )
      end

      def preview_best_warehouse(variant_ids)
        return Inventory::WarehouseResolver.primary if variant_ids.empty?

        warehouse_id = StockItem.joins(:warehouse)
          .where(variant_id: variant_ids, warehouses: { active: true })
          .group(:warehouse_id)
          .order(Arel.sql("SUM(stock_items.quantity_on_hand - stock_items.quantity_reserved - stock_items.quantity_unavailable) DESC"))
          .limit(1)
          .pluck(:warehouse_id)
          .first
        Warehouse.find_by(id: warehouse_id) || Inventory::WarehouseResolver.primary
      end

      def availability_for(variant_ids)
        StockItem.includes(:warehouse)
          .where(variant_id: variant_ids)
          .group_by(&:variant_id)
          .transform_values do |items|
            items.map do |stock_item|
              {
                stock_item_id: stock_item.id,
                warehouse_id: stock_item.warehouse_id,
                warehouse_name: stock_item.warehouse&.name,
                available: stock_item.available,
                on_hand: stock_item.quantity_on_hand,
                reserved: stock_item.quantity_reserved,
                unavailable: stock_item.quantity_unavailable
              }
            end
          end
      end

      def export_scope
        authorize Order
        apply_sort(filtered_scope)
      end

      def export_columns
        {
          "Order #"          => :order_number,
          "External #"       => :external_number,
          "Source"           => :source,
          "Status"           => :status,
          "Financial Status" => :financial_status,
          "Customer Email"   => :customer_email,
          "Customer Name"    => :customer_name,
          "Total"            => :total_price,
          "Currency"         => :currency,
          "Placed At"        => :placed_at,
          "Shopify Id"       => :shopify_order_id
        }
      end
    end
  end
end
