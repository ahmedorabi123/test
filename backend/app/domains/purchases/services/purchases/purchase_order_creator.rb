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
        currency:      (@attrs[:currency] || supplier.currency || "EGP").to_s,
        status:        "draft",
        expected_at:   @attrs[:expected_at],
        notes:         @attrs[:notes],
        created_by_id: @attrs[:created_by_id]
      )

      items.each do |li|
        variant = li[:variant_id].present? ? Variant.find(li[:variant_id]) : nil
        qty     = li[:quantity_ordered].to_i

        # Guard: a Shopify-origin warehouse must only receive Shopify-origin
        # variants. Otherwise the resulting receive would create stock for a
        # manual variant at a Shopify location, which Shopify cannot reflect
        # and would drift on the next inventory sync.
        if variant && warehouse&.shopify_origin? && !variant.shopify_origin?
          raise InvalidInput,
                "Variant #{variant.sku || variant.id} is manual and cannot be ordered into Shopify-origin warehouse #{warehouse.code}"
        end

        # Phase 1: factory POs are inventory-only; costs are not captured on
        # the PO. Store zeroed monetary fields to keep the schema dormant.
        po.line_items.build(
          variant:           variant,
          sku:               li[:sku] || variant&.sku,
          title:             li[:title] || variant&.title || variant&.product&.title,
          quantity_ordered:  qty,
          unit_cost:         0.to_d,
          subtotal:          0.to_d
        )
      end

      compute_totals(po)
      po.save!
      po
    end

    private

    def compute_totals(po)
      po.subtotal        = 0.to_d
      po.total_tax       = 0.to_d
      po.total_shipping  = 0.to_d
      po.total           = 0.to_d
    end
  end
end
