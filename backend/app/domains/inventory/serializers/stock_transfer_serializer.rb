class StockTransferSerializer
  def self.call(transfer, include_lines: true, include_movements: false)
    h = {
      id:                  transfer.id,
      reference:           transfer.reference,
      status:              transfer.status,
      reason:              transfer.reason,
      note:                transfer.note,
      from_warehouse_id:   transfer.from_warehouse_id,
      to_warehouse_id:     transfer.to_warehouse_id,
      from_warehouse_code: transfer.from_warehouse&.code,
      to_warehouse_code:   transfer.to_warehouse&.code,
      from_warehouse_name: transfer.from_warehouse&.name,
      to_warehouse_name:   transfer.to_warehouse&.name,
      posted_at:           transfer.posted_at,
      posted_by_user_id:   transfer.posted_by_user_id,
      created_at:          transfer.created_at,
      updated_at:          transfer.updated_at,
      total_quantity:      transfer.total_quantity,
      line_count:          transfer.stock_transfer_lines.size
    }
    if include_lines
      h[:lines] = transfer.stock_transfer_lines.includes(:variant => :product).map do |line|
        {
          id:            line.id,
          variant_id:    line.variant_id,
          sku:           line.variant&.sku,
          variant_title: line.variant&.title,
          product_title: line.variant&.product&.title,
          quantity:      line.quantity
        }
      end
    end
    if include_movements
      line_ids = transfer.stock_transfer_lines.pluck(:id).map(&:to_s)
      movements = StockMovement
                    .where(reference_type: "StockTransferLine", reference_id: line_ids)
                    .order(:created_at)
      h[:movements] = movements.map do |m|
        {
          id:               m.id,
          stock_item_id:    m.stock_item_id,
          delta:            m.delta,
          reason:           m.reason,
          snapshot_before:  m.snapshot_before,
          snapshot_after:   m.snapshot_after,
          reference_id:     m.reference_id,
          created_at:       m.created_at
        }
      end
    end
    h
  end
end
