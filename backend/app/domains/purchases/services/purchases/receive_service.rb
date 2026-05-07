require "digest"

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

      PurchaseOrder.transaction do
        receipt_values = []
        @receipts.each do |r|
          receipt_values << apply_receipt(r)
        end
        update_status!
        receipt_values.compact!
        post_inventory_journal!(receipt_values) if receipt_values.sum { |row| row[:goods_amount] }.positive?
        @po.reload
      end
      @po
    end

    private

    def post_inventory_journal!(receipt_values)
      amounts = receipt_amounts(receipt_values)
      return if amounts[:total].zero?

      idem_key = receipt_idempotency_key(receipt_values)
      return if JournalEntry.exists?(idempotency_key: idem_key)

      lines = [
        { account_code: "1200", side: "debit", amount: amounts[:inventory],
          description: "Inventory received - PO #{@po.po_number}" }
      ]
      if amounts[:tax].positive?
        lines << { account_code: "1300", side: "debit", amount: amounts[:tax],
                   description: "Recoverable VAT - PO #{@po.po_number}" }
      end
      if amounts[:shipping].positive?
        lines << { account_code: "1200", side: "debit", amount: amounts[:shipping],
                   description: "Inbound freight capitalized - PO #{@po.po_number}" }
      end
      lines << { account_code: "2000", side: "credit", amount: amounts[:total],
                 description: "A/P - #{@po.supplier&.name || @po.supplier_id}" }

      JournalEntry.post!(
        {
          entry_date:      Date.current,
          description:     "Inventory received - PO #{@po.po_number}",
          currency:        (@po.currency.presence || "EGP").upcase,
          source_type:     "purchase_order",
          source_id:       @po.id,
          entry_type:      "purchase",
          idempotency_key: idem_key
        },
        lines
      )
    end

    def apply_receipt(r)
      r = (r.respond_to?(:to_unsafe_h) ? r.to_unsafe_h : r).with_indifferent_access
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
      {
        line_item_id: li.id,
        quantity: qty,
        received_after: li.quantity_received,
        goods_amount: (li.unit_cost.to_d * qty).round(2)
      }
    end

    def receipt_amounts(receipt_values)
      goods_amount = receipt_values.sum { |row| row[:goods_amount] }.to_d.round(2)
      ratio = receipt_ratio(goods_amount)
      tax_amount = (@po.total_tax.to_d * ratio).round(2)
      shipping_amount = (@po.total_shipping.to_d * ratio).round(2)
      {
        inventory: goods_amount,
        tax: tax_amount,
        shipping: shipping_amount,
        total: (goods_amount + tax_amount + shipping_amount).round(2)
      }
    end

    def receipt_ratio(goods_amount)
      subtotal = @po.subtotal.to_d
      subtotal = @po.line_items.sum { |li| li.unit_cost.to_d * li.quantity_ordered }.to_d if subtotal.zero?
      return 0.to_d if subtotal.zero?

      [(goods_amount / subtotal), 1.to_d].min
    end

    def receipt_idempotency_key(receipt_values)
      normalized = receipt_values
        .sort_by { |row| row[:line_item_id].to_s }
        .map { |row| "#{row[:line_item_id]}:#{row[:quantity]}:#{row[:received_after]}" }
        .join("|")
      digest = Digest::SHA256.hexdigest("#{@po.id}:#{@warehouse.id}:#{normalized}")[0, 24]
      "po-receive-#{@po.id}-#{digest}"
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
