module Purchases
  # Receives inventory against a purchase order (Phase 1: inventory-only).
  # For each incoming line:
  #   - resolves the stock item (variant + warehouse; creates if missing)
  #   - bumps line_item.quantity_received
  #   - writes an Inventory::StockMovement (reason: "received")
  # Phase 1 explicitly does NOT post a JournalEntry, record a StockCostLayer,
  # or update Variant#last_purchase_cost; factory POs have no accounting impact.
  # Flips PO.status to "partial" / "received" depending on totals.
  class ReceiveService
    class InvalidInput < StandardError; end
    class MissingWarehouse < StandardError; end

    # receipts: [{ line_item_id:, quantity: }]
    def self.call(purchase_order:, receipts:, warehouse: nil)
      new(purchase_order, receipts, warehouse).call
    end

    def initialize(purchase_order, receipts, warehouse)
      @po         = purchase_order
      @receipts   = Array(receipts)
      @warehouse  = warehouse || purchase_order.warehouse
    end

    def call
      raise InvalidInput, "receipts required" if @receipts.empty?
      raise MissingWarehouse, "warehouse required to receive inventory" if @warehouse.nil?

      PurchaseOrder.transaction do
        @receipts.each { |r| apply_receipt(r) }
        update_status!
        @po.reload
      end
      @po
    end

    private

    def apply_receipt(r)
      r = (r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : r).with_indifferent_access
      qty = r[:quantity].to_i
      return if qty <= 0

      li = @po.line_items.find(r[:line_item_id])
      raise InvalidInput, "line item #{li.id} has no variant" if li.variant_id.nil?

      stock_item = StockItem.find_or_create_by!(variant_id: li.variant_id,
                                                warehouse_id: @warehouse.id) do |si|
        si.quantity_on_hand = 0
      end

      ::Shopify::Origin.without_read_only do
        Inventory::WriteMovement.call(
          stock_item: stock_item,
          delta:      qty,
          reason:     "received",
          reference:  @po
        )
      end

      li.update!(quantity_received: li.quantity_received + qty)
    end

    def update_status!
      new_status =
        if @po.fully_received?
          "received"
        elsif @po.any_received?
          "partial"
        else
          @po.status
        end

      @po.update!(status: new_status, received_at: (@po.fully_received? ? Time.current : @po.received_at))
    end
  end
end
