module Purchases
  # Builds a PurchaseOrder + line items from a params hash.
  class PurchaseOrderCreator
    class InvalidInput < StandardError; end

    def self.call(attrs)
      new(attrs).call
    end

    def initialize(attrs)
      @attrs = attrs.to_h.with_indifferent_access
    end

    def call
      items = Array(@attrs[:line_items])
      raise InvalidInput, "line_items required" if items.empty?

      supplier = Supplier.find(@attrs[:supplier_id])
      warehouse = @attrs[:warehouse_id].present? ? Warehouse.find(@attrs[:warehouse_id]) : nil

      po = PurchaseOrder.new(
        supplier:      supplier,
        warehouse:     warehouse,
        currency:      (@attrs[:currency] || supplier.currency || "USD").to_s,
        status:        "draft",
        expected_at:   @attrs[:expected_at],
        notes:         @attrs[:notes],
        created_by_id: @attrs[:created_by_id]
      )

      items.each do |li|
        variant = li[:variant_id].present? ? Variant.find(li[:variant_id]) : nil
        qty     = li[:quantity_ordered].to_i
        cost    = (li[:unit_cost] || variant&.price || 0).to_d

        po.line_items.build(
          variant:           variant,
          sku:               li[:sku] || variant&.sku,
          title:             li[:title] || variant&.title || variant&.product&.title,
          quantity_ordered:  qty,
          unit_cost:         cost,
          subtotal:          (cost * qty).round(2)
        )
      end

      compute_totals(po)
      po.save!
      po
    end

    private

    def compute_totals(po)
      subtotal = po.line_items.sum { |li| li.subtotal.to_d }
      tax      = @attrs[:total_tax].to_d
      ship     = @attrs[:total_shipping].to_d
      po.subtotal        = subtotal
      po.total_tax       = tax
      po.total_shipping  = ship
      po.total           = subtotal + tax + ship
    end
  end
end
