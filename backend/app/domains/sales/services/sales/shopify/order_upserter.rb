module Sales
  module Shopify
    # Idempotently upserts a Shopify order payload (REST webhook shape) into
    # the ERP sales domain. Variants are looked up by shopify_variant_id when
    # available so line items can link back to our catalog.
    class OrderUpserter
      def self.call(payload, from: :webhook)
        new(payload, from: from).call
      end

      def initialize(payload, from:)
        @payload = payload.with_indifferent_access
        @from    = from.to_sym
      end

      def call
        ::Shopify::Origin.without_read_only do
          ActiveRecord::Base.transaction do
            order = ::Order.find_by(shopify_order_id: payload[:id].to_i)
            # Fall back: claim a locally-seeded order that has the same number
            # but no shopify_order_id yet (happens during first backfill).
            order ||= ::Order.find_by(order_number: (payload[:name].presence || "SH-#{payload[:id]}"),
                                      shopify_order_id: nil)
            order ||= ::Order.new
            # Don't overwrite newer local state with an older Shopify payload.
            if order.persisted? && order.shopify_updated_at.present? && shopify_updated_at_time.present? &&
               order.shopify_updated_at >= shopify_updated_at_time
              return order
            end

            order.assign_attributes(build_order_attrs)
            order.save!
            upsert_line_items(order)
            trigger_accounting(order)
            manage_reservations(order)
            recompute_customer_stats(order)
            order
          end
        end
      end

      private

      attr_reader :payload, :from

      def build_order_attrs
        sc_id   = payload.dig(:customer, :id).presence&.to_i
        cust    = sc_id ? ::Customer.find_by(shopify_customer_id: sc_id) : nil
        loc_id  = payload[:location_id].presence&.to_i ||
                  payload.dig(:fulfillments, 0, :location_id).presence&.to_i

        {
          source:             "shopify",
          shopify_order_id:   payload[:id].presence&.to_i,
          external_number:    payload[:name].presence,
          status:             map_status,
          financial_status:   map_financial_status,
          fulfillment_status: payload[:fulfillment_status].presence,
          currency:           (payload[:currency].presence || "EGP").upcase,
          subtotal_price:     to_decimal(payload[:subtotal_price]),
          total_tax:          to_decimal(payload[:total_tax]),
          total_shipping:     extract_total_shipping,
          total_discount:     to_decimal(payload[:total_discounts]),
          total_price:        to_decimal(payload[:total_price]),
          customer_email:     payload[:email] || payload.dig(:customer, :email),
          customer_name:      extract_customer_name,
          customer_id:        cust&.id,
          shopify_customer_id: sc_id,
          location_id:        loc_id,
          shipping_address:   payload[:shipping_address].is_a?(Hash) ? payload[:shipping_address].to_h : {},
          billing_address:    payload[:billing_address].is_a?(Hash)  ? payload[:billing_address].to_h  : {},
          notes:              payload[:note],
          placed_at:          parse_time(payload[:processed_at] || payload[:created_at]) || Time.current,
          cancelled_at:       parse_time(payload[:cancelled_at]),
          shopify_updated_at: shopify_updated_at_time,
          tags:                   normalize_tags(payload[:tags]),
          delivery_method:        Array(payload[:shipping_lines]).first&.dig(:title) ||
                                  Array(payload[:shipping_lines]).first&.dig("title"),
          items_count:            Array(payload[:line_items]).sum { |li| li[:quantity].to_i },
          payment_gateway_names:  Array(payload[:payment_gateway_names]),
          risk_level:             extract_risk_level,
          cancel_reason:          payload[:cancel_reason],
          closed_at:              parse_time(payload[:closed_at]),
          total_outstanding:      to_decimal(payload[:total_outstanding]),
          shopify_order_status_url: payload[:order_status_url]
        }.tap do |h|
          # Shopify's "name" is already unique per store ("#1001"). Use it for the
          # order_number as well so UI can show the familiar Shopify number.
          h[:order_number] = payload[:name].presence || "SH-#{payload[:id]}"
        end
      end

      def upsert_line_items(order)
        incoming = Array(payload[:line_items])
        keep_ids = []

        incoming.each do |li|
          lh = li.with_indifferent_access
          item = order.line_items.find_or_initialize_by(shopify_line_item_id: lh[:id].to_i)

          variant = lh[:variant_id].present? ? Variant.find_by(shopify_variant_id: lh[:variant_id].to_i) : nil
          qty   = lh[:quantity].to_i
          price = to_decimal(lh[:price])
          disc  = extract_line_discount(lh)

          item.assign_attributes(
            variant:        variant,
            sku:            lh[:sku].presence,
            title:          lh[:title].presence || "Line Item",
            variant_title:  lh[:variant_title].presence,
            quantity:       qty.positive? ? qty : 1,
            price:          price,
            total_discount: disc,
            total_tax:      extract_line_tax(lh),
            line_total:     (price * qty) - disc
          )
          item.save!
          keep_ids << item.id
        end

        order.line_items.where.not(id: keep_ids).destroy_all if incoming.any?
      end

      # Trigger accounting side-effects based on financial status.
      # PostSaleJournalHandler is idempotent per order (idempotency_key).
      # Refund accounting is handled per-refund by RefundUpserter — we do NOT
      # call RefundReversalHandler here to avoid double-counting when partial
      # refund journal entries already exist.
      def trigger_accounting(order)
        case order.financial_status
        when "paid"
          ::Accounting::PostSaleJournalHandler.call(order)
        end
      rescue => e
        Rails.logger.error("[OrderUpserter] Accounting error for order #{order.id}: #{e.message}")
      end

      # Reserve stock when order is new/pending; release when fulfilled or cancelled.
      def manage_reservations(order)
        case order.status
        when "pending", "processing"
          ::Inventory::SyncOrderReservations.call(order)
        when "cancelled", "refunded"
          ::Inventory::ReleaseOrderReservations.call(order)
        end
      rescue => e
        Rails.logger.error("[OrderUpserter] Reservation error for order #{order.id}: #{e.message}")
      end

      def recompute_customer_stats(order)
        return unless order.customer

        ::Crm::CustomerStatsRecomputer.call(order.customer)
      rescue => e
        Rails.logger.error("[OrderUpserter] Customer stats error for order #{order.id}: #{e.message}")
      end

      def map_status
        return "cancelled" if payload[:cancelled_at].present?
        case payload[:fulfillment_status].to_s
        when "fulfilled" then "fulfilled"
        when "partial"   then "processing"
        else
          payload[:financial_status].to_s == "refunded" ? "refunded" : "pending"
        end
      end

      def map_financial_status
        val = payload[:financial_status].to_s
        ::Order::FINANCIAL_STATUSES.include?(val) ? val : "pending"
      end

      def extract_total_shipping
        lines = Array(payload[:shipping_lines])
        lines.sum { |l| to_decimal(l["price"] || l[:price]) }
      end

      def extract_risk_level
        # Shopify's risks API returns recommendation strings; here we accept either
        # a top-level :risk_level (some webhooks include it) or fall back to nil.
        payload[:risk_level].presence ||
          Array(payload[:risks]).map { |r| r[:recommendation] || r["recommendation"] }.compact.last
      end

      def normalize_tags(tags)
        case tags
        when Array  then tags.map(&:to_s).map(&:strip).reject(&:blank?)
        when String then tags.split(",").map(&:strip).reject(&:blank?)
        else []
        end
      end

      def extract_customer_name
        c = payload[:customer] || {}
        [c[:first_name], c[:last_name]].compact.join(" ").presence ||
          [payload.dig(:shipping_address, :first_name), payload.dig(:shipping_address, :last_name)].compact.join(" ").presence
      end

      def extract_line_discount(lh)
        allocs = Array(lh[:discount_allocations])
        allocs.sum { |a| to_decimal(a["amount"] || a[:amount]) }
      end

      def extract_line_tax(lh)
        taxes = Array(lh[:tax_lines])
        taxes.sum { |t| to_decimal(t["price"] || t[:price]) }
      end

      def shopify_updated_at_time
        @shopify_updated_at_time ||= parse_time(payload[:updated_at])
      end

      def to_decimal(val)
        return 0.to_d if val.blank?
        val.to_s.to_d
      rescue ArgumentError
        0.to_d
      end

      def parse_time(v)
        return nil if v.blank?
        v.is_a?(Time) || v.is_a?(ActiveSupport::TimeWithZone) ? v : Time.zone.parse(v.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
