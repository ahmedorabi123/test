module Api
  module V1
    # Single aggregated endpoint that powers the ERP cockpit dashboard.
    # Designed to be small and fast: one request, no N+1, no payloads larger
    # than a few KB. Heavy reporting lives in dedicated services elsewhere.
    class DashboardController < ApplicationController
      def summary
        # Permission gate: any signed-in user with at least one of the core
        # read permissions can see the dashboard (admins bypass).
        unless current_user.admin? || current_user.can?(:orders, :read) || current_user.can?(:inventory, :read)
          return render_error(403, "forbidden", "You are not authorized to view the dashboard")
        end

        window = (params[:window].presence || 30).to_i
        window = 30 if window <= 0 || window > 365
        since  = window.days.ago.beginning_of_day

        render json: {
          data: {
            window_days:        window,
            kpis:               kpis(since),
            revenue_trend:      revenue_trend(since, window),
            orders_by_status:   orders_by_status(since),
            delivery_breakdown: delivery_breakdown,
            low_stock:          low_stock,
            top_variants:       top_variants(since),
            gross_margin:       gross_margin(since),
            recent_activity:    recent_activity
          }
        }
      end

      private

      def kpis(since)
        non_cancelled = Order.where("placed_at >= ?", since).where.not(status: "cancelled")
        ar_balance = Account.find_by(code: "1100")&.balance || 0
        pending_refunds = Refund.where(status: %w[draft approved])

        {
          revenue:             non_cancelled.sum(:total_price).to_f,
          orders_count:        Order.where("placed_at >= ?", since).count,
          ar_outstanding:      ar_balance.to_f,
          pending_shipments:   Fulfillment.where(delivery_status: %w[pending in_transit])
                                          .where("created_at >= ?", since).count,
          pending_refunds:     pending_refunds.count,
          pending_refund_amount: pending_refunds.sum(:amount).to_f,
          low_stock_count:     StockItem.low_stock.count,
          orders_pending:      Order.where(status: "pending").count
        }
      end

      def revenue_trend(since, window)
        rows = Order.where("placed_at >= ?", since)
                    .where.not(status: "cancelled")
                    .group(Arel.sql("DATE(placed_at)"))
                    .sum(:total_price)
        orders_per_day = Order.where("placed_at >= ?", since)
                              .group(Arel.sql("DATE(placed_at)"))
                              .count

        (0...window).map do |offset|
          date = (Date.current - (window - 1 - offset)).to_s
          {
            date:    date,
            revenue: rows[Date.parse(date)].to_f,
            orders:  orders_per_day[Date.parse(date)].to_i
          }
        end
      end

      def orders_by_status(since)
        Order.where("placed_at >= ?", since).group(:status).count
      end

      def delivery_breakdown
        Fulfillment.where(status: "success").group(:delivery_status).count.transform_keys { |k| k || "pending" }
      end

      def low_stock
        StockItem.low_stock
                 .includes(:warehouse, variant: :product)
                 .order(Arel.sql("(quantity_on_hand - quantity_reserved - quantity_unavailable) ASC"))
                 .limit(5)
                 .map do |si|
          {
            id:               si.id,
            warehouse:        si.warehouse&.name,
            variant_id:       si.variant_id,
            sku:              si.variant&.sku,
            product:          si.variant&.product&.title,
            available:        si.available,
            on_hand:          si.quantity_on_hand,
            reserved:         si.quantity_reserved,
            threshold:        si.low_stock_threshold
          }
        end
      end

      def top_variants(since)
        OrderLineItem.joins(:order)
                     .where(orders: { placed_at: since.. })
                     .where.not(orders: { status: "cancelled" })
                     .group(:variant_id, :title, :sku)
                     .order(Arel.sql("SUM(quantity * price) DESC NULLS LAST"))
                     .limit(5)
                     .pluck(
                       :variant_id, :title, :sku,
                       Arel.sql("SUM(quantity) AS qty"),
                       Arel.sql("SUM(quantity * price) AS revenue")
                     )
                     .map { |vid, title, sku, qty, rev| { variant_id: vid, title: title, sku: sku, quantity: qty.to_i, revenue: rev.to_f } }
      end

      def gross_margin(since)
        revenue = Order.where("placed_at >= ?", since).where.not(status: "cancelled").sum(:total_price).to_f
        cogs_lines = JournalLine.joins(:journal_entry, :account)
                                .where(accounts: { code: "5000" })
                                .where("journal_entries.entry_date >= ?", since.to_date)
        cogs = cogs_lines.where(side: "debit").sum(:amount).to_f -
               cogs_lines.where(side: "credit").sum(:amount).to_f
        margin = revenue - cogs
        pct = revenue.positive? ? (margin / revenue * 100.0).round(2) : 0.0
        { revenue: revenue, cogs: cogs, margin: margin, margin_pct: pct }
      end

      def recent_activity
        items = []
        Order.order(created_at: :desc).limit(5).each do |o|
          items << {
            kind: "order",
            at:   o.created_at,
            title: "Order #{o.order_number}",
            subtitle: "#{o.customer_name.presence || 'Guest'} · #{o.financial_status} · #{o.status}",
            amount: o.total_price.to_f,
            currency: o.currency,
            link:  "/orders/#{o.id}"
          }
        end
        Fulfillment.order(created_at: :desc).limit(5).each do |f|
          items << {
            kind: "shipment",
            at:   f.created_at,
            title: "Shipment #{f.tracking_company} #{f.tracking_number}",
            subtitle: "Order #{f.order&.order_number} · #{f.delivery_status || 'pending'}",
            link:  "/shipments/#{f.id}"
          }
        end
        Refund.order(created_at: :desc).limit(5).each do |r|
          items << {
            kind: "refund",
            at:   r.created_at,
            title: "Refund #{r.kind || 'manual'}",
            subtitle: "Order #{r.order&.order_number} · #{r.status}",
            amount: r.amount.to_f,
            currency: r.currency,
            link:  "/refunds/#{r.id}"
          }
        end
        items.sort_by { |i| i[:at] || Time.at(0) }.reverse.first(10)
      end
    end
  end
end
