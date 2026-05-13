module Sales
  # Posts a periodic sales report from a consignment showroom.
  #
  # Input:
  #   {
  #     warehouse_id:   <uuid of consignment warehouse>,
  #     period:         "2025-01"  # YYYY-MM
  #     report_date:    "2025-02-01"  # optional, when settlement is dated
  #     currency:       "EGP"  # optional, defaults to warehouse currency or EGP
  #     line_items:     [{ variant_id:, quantity:, unit_price: }, ...]
  #     notes:          "..." # optional
  #     actor:          User # optional, recorded on the reversal aggregate
  #   }
  #
  # Quantity sign semantics:
  # * quantity > 0  → sales line. Builds an OrderLineItem, deducts stock at
  #   the consignment warehouse (strict — no clamping), feeds the sale
  #   journal + COGS journal.
  # * quantity < 0  → accounting-only sales reversal. Does NOT create an
  #   OrderLineItem, does NOT move physical stock, does NOT create a Refund.
  #   Aggregated into a +ShowroomReversal+ that posts a single reversal
  #   journal (DR 4000 / CR 1100) via +Accounting::PostShowroomReversalHandler+.
  # * quantity = 0  → rejected.
  #
  # Idempotency: a given (warehouse, period) tuple is immutable. Re-running
  # the same report (positive lines, negative lines, or both) is a no-op:
  # rejected with +AlreadyPosted+. The Order's "[showroom:<code>:<period>]"
  # note tag AND any existing +ShowroomReversal+ for the period are checked.
  #
  # Atomicity: the order, its line items, all stock movements, the sale
  # journal, the COGS journal, the reversal record, and the reversal journal
  # are wrapped in a single +ActiveRecord::Base.transaction+. Any failure —
  # including journal posting — rolls back the whole report.
  class ShowroomSalesReportPoster
    class InvalidInput  < StandardError; end
    class AlreadyPosted < StandardError; end

    Result = Struct.new(:order, :reversal, :sales_total, :reversal_total, keyword_init: true) do
      def order_id        = order&.id
      def order_number    = order&.order_number
      def reversal_id     = reversal&.id
      def idempotency_key = reversal&.idempotency_key
    end

    def self.call(attrs)
      new(attrs).call
    end

    def initialize(attrs)
      @attrs = attrs.to_h.with_indifferent_access
      @actor = @attrs.delete(:actor)
    end

    def call
      validate!
      warehouse = Warehouse.find(@attrs[:warehouse_id])
      raise InvalidInput, "warehouse must be consignment" unless warehouse.kind == "consignment"

      sales_lines, reversal_lines = split_lines!
      check_idempotency!(warehouse, @attrs[:period])

      ActiveRecord::Base.transaction do
        order    = nil
        reversal = nil

        if sales_lines.any?
          order = build_order(warehouse, sales_lines)
          deduct_inventory(order, warehouse)
          post_sale_journals(order)
        end

        if reversal_lines.any?
          reversal = build_reversal(warehouse, reversal_lines)
          Accounting::PostShowroomReversalHandler.call(reversal)
        end

        Result.new(
          order:           order,
          reversal:        reversal,
          sales_total:     sales_lines.sum { |li| li[:quantity].to_i * li[:unit_price].to_d },
          reversal_total:  reversal_lines.sum { |li| li[:quantity].to_i.abs * li[:unit_price].to_d }
        )
      end
    end

    private

    def validate!
      raise InvalidInput, "warehouse_id required"        if @attrs[:warehouse_id].blank?
      raise InvalidInput, "period must be YYYY-MM"       unless @attrs[:period].to_s =~ /\A\d{4}-\d{2}\z/
      raise InvalidInput, "line_items required"          if Array(@attrs[:line_items]).empty?
    end

    # Splits incoming line_items into positive (sales) and negative (reversal)
    # groups, after rejecting zero-qty rows and duplicate +(variant_id, sign)+
    # pairs.
    def split_lines!
      raw = Array(@attrs[:line_items]).map { |li| li.to_h.with_indifferent_access }

      raw.each do |li|
        raise InvalidInput, "variant_id required on every line" if li[:variant_id].blank?
        raise InvalidInput, "quantity must not be zero"         if li[:quantity].to_i == 0
        raise InvalidInput, "unit_price must be present"        if li[:unit_price].to_s.strip.empty?
      end

      grouped = raw.group_by { |li| [li[:variant_id], li[:quantity].to_i.positive? ? :pos : :neg] }
      duplicates = grouped.select { |_, rows| rows.size > 1 }
      if duplicates.any?
        offending = duplicates.keys.map(&:first).uniq
        raise InvalidInput, "duplicate line(s) for variant(s): #{offending.join(', ')}"
      end

      sales    = raw.select { |li| li[:quantity].to_i > 0 }
      reversal = raw.select { |li| li[:quantity].to_i < 0 }
      [sales, reversal]
    end

    def check_idempotency!(warehouse, period)
      tag = showroom_tag(warehouse, period)
      if Order.where("notes LIKE ?", "%#{tag}%").exists?
        raise AlreadyPosted, "Showroom report for #{warehouse.name} #{period} already posted"
      end
      idem_key = ShowroomReversal.build_idempotency_key(warehouse_id: warehouse.id, period: period)
      if ShowroomReversal.exists?(idempotency_key: idem_key)
        raise AlreadyPosted, "Showroom report for #{warehouse.name} #{period} already posted"
      end
    end

    def showroom_tag(warehouse, period)
      "[showroom:#{warehouse.code}:#{period}]"
    end

    def build_order(warehouse, sales_lines)
      currency = (@attrs[:currency].presence || warehouse.currency.presence || "EGP").upcase
      report_date = @attrs[:report_date].present? ? Date.parse(@attrs[:report_date]) : Date.current

      attrs = {
        source:        "showroom",
        currency:      currency,
        customer_name: "#{warehouse.name} – #{@attrs[:period]}",
        notes:         "#{@attrs[:notes].to_s.strip}\n#{showroom_tag(warehouse, @attrs[:period])}".strip,
        line_items:    sales_lines.map { |li|
          { variant_id: li[:variant_id], quantity: li[:quantity], price: li[:unit_price] }
        },
        mark_paid:     false, # we'll transition manually
        skip_reservations: true
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
      @line_costs = {}
      order.line_items.each do |li|
        next unless li.variant_id

        si = StockItem.find_or_create_by!(variant_id: li.variant_id, warehouse_id: warehouse.id) do |s|
          s.quantity_on_hand = 0
        end
        Inventory::WriteMovement.call(
          stock_item: si,
          delta:      -li.quantity,
          reason:     "showroom_sale",
          reference:  order,
          strict:     true
        )
        @line_costs[li.id] = Inventory::ConsumeCostLayers.call(
          stock_item: si,
          quantity: li.quantity,
          reference: nil
        ).total_cost
      end
    end

    # Posts the sale journal + COGS journal. Failures are intentionally
    # allowed to escape so the outer +ActiveRecord::Base.transaction+ rolls
    # back the entire report (order + line items + movements + journals).
    def post_sale_journals(order)
      ::Accounting::PostSaleJournalHandler.call(order)

      total_cogs = order.line_items.sum do |li|
        @line_costs&.[](li.id).presence || begin
          result = Catalog::VariantCostResolver.call(li.variant)
          result.cost * li.quantity.to_i
        end
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
    end

    def build_reversal(warehouse, reversal_lines)
      currency = (@attrs[:currency].presence || warehouse.currency.presence || "EGP").upcase
      total = reversal_lines.sum { |li| li[:quantity].to_i.abs * li[:unit_price].to_d }
      ShowroomReversal.create!(
        warehouse:         warehouse,
        period:            @attrs[:period],
        currency:          currency,
        total_amount:      total,
        lines:             reversal_lines.map { |li|
          { variant_id: li[:variant_id], quantity: li[:quantity].to_i, unit_price: li[:unit_price].to_s }
        },
        idempotency_key:   ShowroomReversal.build_idempotency_key(warehouse_id: warehouse.id, period: @attrs[:period]),
        notes:             @attrs[:notes].presence,
        posted_at:         Time.current,
        posted_by_user_id: @actor&.id
      )
    end
  end
end
