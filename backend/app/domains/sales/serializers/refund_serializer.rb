class RefundSerializer
  def self.call(refund, include_line_items: true)
    {
      id:                 refund.id,
      order_id:           refund.order_id,
      amount:             refund.amount,
      currency:           refund.currency,
      reason:             refund.reason,
      note:               refund.note,
      processed_at:       refund.processed_at,
      shopify_refund_id:  refund.shopify_refund_id,
      partial:            refund.partial?,
      full:               refund.full?,
      restock:            refund.restock,
      inventory_restocked: refund.inventory_restocked,
      transactions:       refund.transactions,
      created_at:         refund.created_at,
      updated_at:         refund.updated_at,
      line_items: include_line_items ? refund.refund_line_items.map { |li| RefundLineItemSerializer.call(li) } : nil
    }.compact
  end
end

class RefundLineItemSerializer
  def self.call(item)
    {
      id:                  item.id,
      refund_id:           item.refund_id,
      order_line_item_id:  item.order_line_item_id,
      quantity:            item.quantity,
      subtotal:            item.subtotal,
      restock_type:        item.restock_type,
      restock:             item.restock,
      location_id:         item.location_id
    }
  end
end
