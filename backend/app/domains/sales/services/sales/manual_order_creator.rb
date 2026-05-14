module Sales
  # Creates a manual/showroom order and (optionally) attaches a customer,
  # then triggers accounting and inventory side-effects just like the
  # Shopify webhook path — but driven by the UI.
  #
  # Input shape:
  #   {
  #     source: "manual" | "showroom",
  #     currency: "USD",
  #     customer_id: <uuid>        # optional — links to CRM customer
  #     customer_email: "...",
  #     customer_name: "...",
  #     notes: "...",
  #     shipping_address: {...},
  #     billing_address:  {...},
  #     line_items: [
  #       { variant_id: <uuid>, sku:, title:, quantity:, price:, total_tax:, total_discount: },
  #       ...
  #     ],
  #     total_shipping: "0.00",
  #     mark_paid: true             # optional — if true, post sale journal + set financial_status=paid
  #   }
  class ManualOrderCreator
    class InvalidInput < StandardError; end

    def self.call(attrs)
      new(attrs).call
    end

    def initialize(attrs)
      @attrs = attrs.to_h.with_indifferent_access
    end

    def call
      validate!

      ActiveRecord::Base.transaction do
        order = build_order
        build_line_items(order)
        compute_totals(order)
        order.save!
        sync_reservations(order) unless skip_reservations?
        # Post sale journal whenever the order ends up paid — not just when
        # the caller passed mark_paid: true. Keeps showroom + manual paths
        # consistent.
        post_accounting(order) if order.financial_status == "paid"
        recompute_customer_stats(order)
        order
      end
    end

    private

    attr_reader :attrs

    def validate!
      raise InvalidInput, "line_items required" if Array(attrs[:line_items]).empty?
      src = attrs[:source].presence || "manual"
      raise InvalidInput, "source must be manual or showroom" unless %w[manual showroom].include?(src)
      raise InvalidInput, "manual and showroom orders cannot use Shopify warehouses" if attrs[:location_id].present?

      if attrs[:warehouse_id].present?
        warehouse = ::Warehouse.find(attrs[:warehouse_id])
        raise InvalidInput, "manual and showroom orders cannot use Shopify warehouses" if warehouse.shopify_origin?
      end
    end

    def build_order
      cust = attrs[:customer_id].present? ? ::Customer.find(attrs[:customer_id]) : nil

      ::Order.new(
        source:           attrs[:source].presence || "manual",
        status:           "pending",
        financial_status: mark_paid? ? "paid" : "pending",
        currency:         (attrs[:currency].presence || "EGP").upcase,
        customer_id:      cust&.id,
        customer_email:   attrs[:customer_email] || cust&.email,
        customer_name:    attrs[:customer_name]  || cust&.display_name,
        location_id:      attrs[:location_id].presence,
        shipping_address: attrs[:shipping_address].is_a?(Hash) ? attrs[:shipping_address] : {},
        billing_address:  attrs[:billing_address].is_a?(Hash)  ? attrs[:billing_address]  : {},
        notes:            attrs[:notes],
        placed_at:        Time.current,
        total_shipping:   to_d(attrs[:total_shipping])
      )
    end

    def build_line_items(order)
      Array(attrs[:line_items]).each do |li|
        lh   = li.to_h.with_indifferent_access
        qty  = lh[:quantity].to_i
        raise InvalidInput, "line_item quantity must be positive" unless qty.positive?
        variant = lh[:variant_id].present? ? ::Variant.find(lh[:variant_id]) : nil
        price   = to_d(lh[:price] || variant&.price)
        disc    = to_d(lh[:total_discount])
        tax     = to_d(lh[:total_tax])

        order.line_items.build(
          variant:        variant,
          sku:            lh[:sku].presence || variant&.sku,
          title:          lh[:title].presence || variant&.product&.title || "Line Item",
          variant_title:  lh[:variant_title].presence || variant&.title,
          quantity:       qty,
          price:          price,
          total_discount: disc,
          total_tax:      tax,
          line_total:     (price * qty) - disc
        )
      end
    end

    def compute_totals(order)
      subtotal = order.line_items.sum { |li| li.price * li.quantity }
      discount = order.line_items.sum(&:total_discount)
      tax      = order.line_items.sum(&:total_tax)

      order.subtotal_price = subtotal
      order.total_tax      = tax
      order.total_discount = discount
      order.total_price    = subtotal - discount + tax + order.total_shipping
    end

    def post_accounting(order)
      ::Accounting::PostSaleJournalHandler.call(order)
    rescue => e
      Rails.logger.error("[ManualOrderCreator] accounting error for #{order.id}: #{e.message}")
    end

    def sync_reservations(order)
      warehouse = attrs[:warehouse_id].present? ? Warehouse.find(attrs[:warehouse_id]) : nil
      ::Inventory::SyncOrderReservations.call(order, warehouse: warehouse)
    end

    def recompute_customer_stats(order)
      return unless order.customer

      ::Crm::CustomerStatsRecomputer.call(order.customer)
    rescue => e
      Rails.logger.error("[ManualOrderCreator] customer stats error for #{order.id}: #{e.message}")
    end

    def mark_paid?
      attrs[:mark_paid].to_s == "true" || attrs[:mark_paid] == true
    end

    def skip_reservations?
      attrs[:skip_reservations].to_s == "true" || attrs[:skip_reservations] == true
    end

    def to_d(v)
      return 0.to_d if v.blank?
      v.to_s.to_d
    rescue ArgumentError
      0.to_d
    end
  end
end
