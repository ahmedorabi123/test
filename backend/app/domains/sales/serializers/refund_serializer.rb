class RefundSerializer
  def self.call(refund, include_line_items: true)
    order = refund.order
    {
      id:                 refund.id,
      order_id:           refund.order_id,
      order:              order ? order_summary(order) : nil,
      customer:           order ? customer_summary(order) : nil,
      amount:             refund.amount,
      currency:           refund.currency,
      reason:             refund.reason,
      note:               refund.note,
      status:             refund.respond_to?(:status) ? refund.status : "processed",
      kind:               refund.respond_to?(:kind) ? refund.kind : (refund.shopify_refund_id.present? ? "shopify" : "manual"),
      content_hash:       refund.respond_to?(:content_hash) ? refund.content_hash : nil,
      processed_at:       refund.processed_at,
      shopify_refund_id:  refund.shopify_refund_id,
      partial:            refund.partial?,
      full:               refund.full?,
      restock:            refund.restock,
      inventory_restocked: refund.inventory_restocked,
      journal_entry_id:    refund_journal_entry_id(refund),
      transactions:       refund.transactions,
      created_at:         refund.created_at,
      updated_at:         refund.updated_at,
      line_items: include_line_items ? refund.refund_line_items.map { |li| RefundLineItemSerializer.call(li) } : nil
    }.compact
  end

  def self.refund_journal_entry_id(refund)
    JournalEntry.where(source_type: "refund", source_id: refund.id, entry_type: "refund")
                .order(created_at: :desc)
                .limit(1)
                .pick(:id)
  end

  def self.order_summary(order)
    {
      id: order.id,
      order_number: order.order_number,
      total_price: order.total_price,
      total_refunded: order.respond_to?(:total_refunded) ? order.total_refunded : order.refunds.sum(:amount),
      currency: order.currency,
      status: order.status,
      financial_status: order.financial_status
    }
  end

  def self.customer_summary(order)
    {
      id: order.customer_id,
      name: order.customer_name,
      email: order.customer_email,
      phone: order.customer&.phone
    }
  end
end

class RefundLineItemSerializer
  def self.call(item)
    order_line_item = item.order_line_item
    {
      id:                  item.id,
      refund_id:           item.refund_id,
      order_line_item_id:  item.order_line_item_id,
      title:               order_line_item&.title,
      sku:                 order_line_item&.sku,
      variant_title:       order_line_item&.variant_title,
      quantity:            item.quantity,
      subtotal:            item.subtotal,
      restock_type:        item.restock_type,
      restock:             item.restock,
      location_id:         item.location_id
    }
  end
end
