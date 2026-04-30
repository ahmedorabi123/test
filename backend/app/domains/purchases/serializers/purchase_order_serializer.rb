module Purchases
  module Serializers
    class PurchaseOrderLineItemSerializer
      def self.call(li)
        {
          id:                li.id,
          purchase_order_id: li.purchase_order_id,
          variant_id:        li.variant_id,
          sku:               li.sku,
          title:             li.title,
          quantity_ordered:  li.quantity_ordered,
          quantity_received: li.quantity_received,
          remaining:         li.remaining,
          unit_cost:         li.unit_cost,
          subtotal:          li.subtotal
        }
      end
    end

    class PurchaseOrderSerializer
      def self.call(po, include_line_items: true)
        {
          id:             po.id,
          po_number:      po.po_number,
          supplier_id:    po.supplier_id,
          supplier_name:  po.supplier&.name,
          warehouse_id:   po.warehouse_id,
          warehouse_name: po.warehouse&.name,
          status:         po.status,
          currency:       po.currency,
          subtotal:       po.subtotal,
          total_tax:      po.total_tax,
          total_shipping: po.total_shipping,
          total:          po.total,
          ordered_at:     po.ordered_at,
          expected_at:    po.expected_at,
          received_at:    po.received_at,
          notes:          po.notes,
          created_by_id:  po.created_by_id,
          created_at:     po.created_at,
          updated_at:     po.updated_at,
          line_items:     include_line_items ? po.line_items.map { |li| PurchaseOrderLineItemSerializer.call(li) } : nil
        }.compact
      end
    end
  end
end

PurchaseOrderSerializer         = Purchases::Serializers::PurchaseOrderSerializer
PurchaseOrderLineItemSerializer = Purchases::Serializers::PurchaseOrderLineItemSerializer
