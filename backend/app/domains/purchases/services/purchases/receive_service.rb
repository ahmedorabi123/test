module Purchases
  # Receives inventory against a purchase order. For each incoming line:
  #   - resolves the stock item (variant + warehouse; creates if missing)
  #   - bumps line_item.quantity_received
  #   - writes an Inventory::StockMovement (reason: "received")
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

      total_value = 0.to_d
      PurchaseOrder.transaction do
        @receipts.each do |r|
          total_value += apply_receipt(r)
        end
        update_status!
        @po.reload
      end
      post_inventory_journal!(total_value) if total_value > 0
      @po
    end

    private

    def post_inventory_journal!(amount)
      idem_key = "po-receive-#{@po.id}-#{Time.current.to_f}"
      JournalEntry.post!(
        {
          entry_date:      Date.current,
          description:     "Inventory received – PO #{@po.number}",
          currency:        (@po.currency.presence || "USD").upcase,
          source_type:     "purchase_order",
          source_id:       @po.id,
          entry_type:      "purchase",
          idempotency_key: idem_key
        },
        [
          { account_code: "1200", side: "debit",  amount: amount,
            description: "Inventory received – PO #{@po.number}" },
          { account_code: "2000", side: "credit", amount: amount,
            description: "A/P – #{@po.supplier&.name || @po.supplier_id}" }
        ]
      )
    rescue StandardError => e
      Rails.logger.warn "[ReceiveService] inventory posting failed for PO=#{@po.id}: #{e.message}"
    end

    def apply_receipt(r)
      qty = r[:quantity].to_i
      return 0.to_d if qty <= 0

      li = @po.line_items.find(r[:line_item_id])
      raise InvalidInput, "line item #{li.id} has no variant" if li.variant_id.nil?

      stock_item = StockItem.find_or_create_by!(variant_id: li.variant_id,
                                                warehouse_id: @warehouse.id) do |si|
        si.quantity_on_hand = 0
      end

      Inventory::WriteMovement.call(
        stock_item: stock_item,
        delta:      qty,
        reason:     "received",
        reference:  @po
      )

      li.update!(quantity_received: li.quantity_received + qty)
      (li.unit_cost.to_d * qty)
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
