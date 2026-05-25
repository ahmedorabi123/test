module Purchases
  class EditReceiptService
    class InvalidInput < StandardError; end
    class MissingWarehouse < StandardError; end

    def self.call(purchase_order:, line_items:, actor: nil, request: nil)
      new(purchase_order, line_items, actor: actor, request: request).call
    end

    def initialize(purchase_order, line_items, actor:, request:)
      @po = purchase_order
      @line_items = Array(line_items)
      @actor = actor
      @request = request
    end

    def call
      raise InvalidInput, "line_items required" if @line_items.empty?
      raise MissingWarehouse, "warehouse required to edit received inventory" if @po.warehouse.nil?

      PurchaseOrder.transaction do
        changes = @line_items.filter_map { |line| apply_line_change(line) }
        update_status!
        record_audit(changes) if changes.any?
        @po.reload
      end
    end

    private

    def apply_line_change(line)
      attrs = (line.respond_to?(:to_unsafe_h) ? line.to_unsafe_h : line).with_indifferent_access
      line_item = @po.line_items.find(attrs[:id])
      raise InvalidInput, "line item #{line_item.id} has no variant" if line_item.variant_id.nil?

      new_quantity = attrs[:quantity_received].to_i
      raise InvalidInput, "quantity_received cannot be negative" if new_quantity.negative?

      old_quantity = line_item.quantity_received.to_i
      delta = new_quantity - old_quantity
      return nil if delta.zero?

      stock_item = StockItem.find_or_create_by!(variant_id: line_item.variant_id, warehouse_id: @po.warehouse_id) do |si|
        si.quantity_on_hand = 0
      end

      ::Shopify::Origin.without_read_only do
        Inventory::WriteMovement.call(
          stock_item: stock_item,
          delta: delta,
          reason: "adjusted",
          reference: @po,
          strict: true,
          note: "PO receipt edit for #{line_item.sku || line_item.title}: #{old_quantity} -> #{new_quantity}"
        )
      end

      line_item.update!(quantity_received: new_quantity)
      { line_item_id: line_item.id, from: old_quantity, to: new_quantity, delta: delta }
    end

    def update_status!
      new_status = if @po.fully_received?
        "received"
      elsif @po.any_received?
        "partial"
      elsif @po.status == "received"
        "ordered"
      else
        @po.status
      end

      @po.update!(status: new_status, received_at: (@po.fully_received? ? (@po.received_at || Time.current) : @po.received_at))
    end

    def record_audit(changes)
      AuditLog.record(
        user: @actor,
        action: "purchase_order.receipt_edited",
        subject: @po,
        request: @request,
        diff: { line_items: changes }
      )
    end
  end
end
