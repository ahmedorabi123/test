module Sales
  # Posts a periodic sales report from a consignment showroom.
  #
  # Input:
  #   {
  #     warehouse_id:   <uuid of consignment warehouse>,
  #     period:         "2025-01"  # YYYY-MM
  #     report_date:    "2025-02-01"  # optional, when settlement is dated
  #     currency:       "USD"  # optional, defaults to warehouse currency or USD
  #     line_items:     [{ variant_id:, quantity:, unit_price: }, ...]
  #     notes:          "..." # optional
  #   }
  #
  # Effect (atomic):
  #   1. Creates an Order with source="showroom", financial_status="paid",
  #      status="fulfilled", customer_name="<warehouse_name> – <period>"
  #   2. Deducts stock from the consignment warehouse via WriteMovement
  #   3. Posts the sales journal (DR A/R, CR Sales) via PostSaleJournalHandler
  #   4. Posts COGS journal (DR 5000, CR 1200) using variant.cost_per_item
  #
  # Idempotent: rejects if an order with the same showroom_id+period exists.
  class ShowroomSalesReportPoster
    class InvalidInput < StandardError; end
    class AlreadyPosted < StandardError; end

    def self.call(attrs)
      new(attrs).call
    end

    def initialize(attrs)
      @attrs = attrs.to_h.with_indifferent_access
    end

    def call
      validate!
      warehouse = Warehouse.find(@attrs[:warehouse_id])
      raise InvalidInput, "warehouse must be consignment" unless warehouse.kind == "consignment"

      check_idempotency!(warehouse, @attrs[:period])

      Order.transaction do
        order = build_order(warehouse)
        deduct_inventory(order, warehouse)
        post_journals(order)
        order
      end
    end

    private

    def validate!
      raise InvalidInput, "warehouse_id required"        if @attrs[:warehouse_id].blank?
      raise InvalidInput, "period must be YYYY-MM"       unless @attrs[:period].to_s =~ /\A\d{4}-\d{2}\z/
      raise InvalidInput, "line_items required"          if Array(@attrs[:line_items]).empty?
    end

    def check_idempotency!(warehouse, period)
      tag = showroom_tag(warehouse, period)
      if Order.where("notes LIKE ?", "%#{tag}%").exists?
        raise AlreadyPosted, "Showroom report for #{warehouse.name} #{period} already posted"
      end
    end

    def showroom_tag(warehouse, period)
      "[showroom:#{warehouse.code}:#{period}]"
    end

    def build_order(warehouse)
      currency = (@attrs[:currency].presence || warehouse.currency.presence || "USD").upcase
      report_date = @attrs[:report_date].present? ? Date.parse(@attrs[:report_date]) : Date.current

      attrs = {
        source:        "showroom",
        currency:      currency,
        customer_name: "#{warehouse.name} – #{@attrs[:period]}",
        notes:         "#{@attrs[:notes].to_s.strip}\n#{showroom_tag(warehouse, @attrs[:period])}".strip,
        line_items:    Array(@attrs[:line_items]).map { |li|
          h = li.to_h.with_indifferent_access
          { variant_id: h[:variant_id], quantity: h[:quantity], price: h[:unit_price] }
        },
        mark_paid:     false # we'll transition manually
      }
      order = Sales::ManualOrderCreator.call(attrs)
      order.update!(
        placed_at:        report_date.to_time,
        location_id:      nil,
        financial_status: "paid",
        status:           "fulfilled"
      )
      order
    end

    def deduct_inventory(order, warehouse)
      order.line_items.each do |li|
        next unless li.variant_id

        si = StockItem.find_or_create_by!(variant_id: li.variant_id, warehouse_id: warehouse.id) do |s|
          s.quantity_on_hand = 0
        end
        Inventory::WriteMovement.call(
          stock_item: si,
          delta:      -li.quantity,
          reason:     "showroom_sale",
          reference:  order
        )
      end
    end

    def post_journals(order)
      ::Accounting::PostSaleJournalHandler.call(order)

      total_cogs = order.line_items.sum do |li|
        cost = li.variant&.cost_per_item.to_d
        cost * li.quantity.to_i
      end
      return if total_cogs <= 0

      idem_key = "cogs-order-#{order.id}"
      return if JournalEntry.exists?(idempotency_key: idem_key)

      JournalEntry.post!(
        {
          entry_date:      order.placed_at&.to_date || Date.current,
          description:     "COGS – Showroom #{order.customer_name}",
          currency:        order.currency,
          source_type:     "order",
          source_id:       order.id,
          entry_type:      "sale",
          idempotency_key: idem_key
        },
        [
          { account_code: "5000", side: "debit",  amount: total_cogs,
            description: "COGS – #{order.customer_name}" },
          { account_code: "1200", side: "credit", amount: total_cogs,
            description: "Inventory consumed – showroom sale" }
        ]
      )
    rescue StandardError => e
      Rails.logger.warn "[ShowroomSalesReportPoster] journal failure: #{e.message}"
    end
  end
end
