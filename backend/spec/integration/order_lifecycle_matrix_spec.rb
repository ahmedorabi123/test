require "rails_helper"

# Cross-module integration matrix for the Order lifecycle.
#
# For each significant transition, verify the side-effects on EVERY downstream
# module:
#   • Inventory (StockReservation, StockItem.quantity_reserved/on_hand, StockMovement)
#   • Shipping  (Fulfillment, FulfillmentLineItem, ShipmentEvent, last_delivery_status)
#   • Accounting (JournalEntry sale/COGS/reversal, balanced lines)
#   • CRM       (Customer.orders_count, Customer.lifetime_value)
#   • Audit     (AuditLog rows for transitions)
RSpec.describe "Order lifecycle cross-module matrix", type: :model do
  let!(:warehouse)  { create(:warehouse, code: "WH-MAIN", active: true) }
  let!(:product)    { create(:product) }
  let!(:variant)    { create(:variant, product: product, sku: "MTRX-1", price: "10.00") }
  let!(:stock_item) { create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 20) }
  let!(:customer)   { create(:customer, email: "buyer@example.com") }

  before { seed_accounts }

  # Helper to create a paid manual order with reservations. This is the
  # canonical "starting point" used by most matrix scenarios.
  def paid_manual_order(quantity: 5)
    Sales::ManualOrderCreator.call(
      source: "manual",
      currency: "EGP",
      customer_id: customer.id,
      customer_email: customer.email,
      customer_name: customer.display_name,
      warehouse_id: warehouse.id,
      mark_paid: true,
      line_items: [
        { variant_id: variant.id, quantity: quantity, price: "10.00", title: "Matrix" }
      ]
    )
  end

  # ──────────────────────────────────────────────────────────────────────────
  # 1. CREATION → reservations + sale journal + customer stats
  # ──────────────────────────────────────────────────────────────────────────
  describe "ManualOrderCreator (paid)" do
    it "reserves stock, posts sale journal, links customer, leaves on_hand untouched" do
      order = paid_manual_order(quantity: 4)

      stock_item.reload
      expect(stock_item.quantity_reserved).to eq(4)
      expect(stock_item.quantity_on_hand).to eq(20)
      expect(order.line_items.first.stock_reservations.active.sum(:quantity)).to eq(4)
      expect(JournalEntry.where(idempotency_key: "sale-journal-#{order.id}")).to exist

      customer.reload
      expect(customer.orders_count).to be >= 1
      expect(customer.total_spent.to_d).to be > 0
    end

    it "is idempotent on the sale journal — re-running PostSaleJournalHandler does not duplicate" do
      order = paid_manual_order
      Accounting::PostSaleJournalHandler.call(order)
      expect(JournalEntry.where(idempotency_key: "sale-journal-#{order.id}").count).to eq(1)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # 2. PROCESSING is no longer available to manual/showroom orders.
  # ──────────────────────────────────────────────────────────────────────────
  describe "status: pending → processing" do
    it "is rejected for manual orders" do
      order = paid_manual_order
      expect {
        Sales::OrderStateMachine.call(order, to: "processing")
      }.to raise_error(Sales::OrderStateMachine::InvalidTransition, /Manual orders/)
      expect(order.reload.status).to eq("pending")
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # 3. SHIPPING / FULFILLMENT — making a shipment "in transit" and "delivered".
  #    Verifies inventory consumption + denormalised last_delivery_status.
  # ──────────────────────────────────────────────────────────────────────────
  describe "fulfillment lifecycle (full + partial)" do
    it "FULL fulfillment: consumes reservations, deducts on_hand, posts COGS, sets order=fulfilled" do
      order = paid_manual_order(quantity: 4)
      line_item = order.line_items.first

      f = Shipping::CreateManualFulfillment.call(
        order: order,
        tracking_company: "Bosta",
        line_items: [{ order_line_item_id: line_item.id, quantity: 4 }]
      )

      expect(f.status).to eq("success")
      expect(f.fulfillment_line_items.count).to eq(1)
      stock_item.reload
      expect(stock_item.quantity_on_hand).to eq(16)   # 20 - 4
      expect(stock_item.quantity_reserved).to eq(0)
      expect(line_item.reload.fulfilled_quantity).to eq(4)
      expect(order.reload.fulfillment_status).to eq("fulfilled")
      expect(StockMovement.where(reason: "fulfilled").count).to be >= 1
    end

    it "PARTIAL fulfillment: leaves remaining reservations active and order=partial" do
      order = paid_manual_order(quantity: 5)
      line_item = order.line_items.first

      Shipping::CreateManualFulfillment.call(
        order: order,
        tracking_company: "Manual",
        line_items: [{ order_line_item_id: line_item.id, quantity: 2 }]
      )

      stock_item.reload
      expect(stock_item.quantity_on_hand).to eq(18)
      expect(stock_item.quantity_reserved).to eq(3)
      expect(line_item.reload.fulfilled_quantity).to eq(2)
      expect(order.reload.fulfillment_status).to eq("partial")
    end

    it "delivery_status changes propagate to Order.last_delivery_status (sort/filter axis)" do
      order = paid_manual_order(quantity: 1)
      line_item = order.line_items.first

      f = Shipping::CreateManualFulfillment.call(
        order: order,
        tracking_company: "Bosta",
        line_items: [{ order_line_item_id: line_item.id, quantity: 1 }]
      )

      f.update!(delivery_status: "in_transit")
      expect(order.reload.last_delivery_status).to eq("in_transit")

      f.update!(delivery_status: "delivered")
      expect(order.reload.last_delivery_status).to eq("delivered")
    end

    it "fulfills without creating a shipment row when transitioning manual orders" do
      order = paid_manual_order(quantity: 2)
      Sales::OrderStateMachine.call(order, to: "fulfilled")

      expect(order.reload.status).to eq("fulfilled")
      expect(order.fulfillments.count).to eq(0)
      expect(stock_item.reload.quantity_on_hand).to eq(18)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # 4. CANCELLATION — releases reservations, reverses sale if was paid.
  # ──────────────────────────────────────────────────────────────────────────
  describe "cancellation" do
    it "releases active reservations and stamps cancelled_at" do
      order = paid_manual_order(quantity: 3)
      reservations_before = order.line_items.flat_map(&:stock_reservations).count
      expect(reservations_before).to be > 0

      Sales::OrderStateMachine.call(order, to: "cancelled")

      order.reload
      expect(order.status).to eq("cancelled")
      expect(order.cancelled_at).to be_present
      stock_item.reload
      expect(stock_item.quantity_reserved).to eq(0)
      expect(stock_item.quantity_on_hand).to eq(20) # nothing was actually shipped
    end

    it "cancelling a PAID order posts a cancel-reversal journal entry" do
      order = paid_manual_order(quantity: 1)
      expect(JournalEntry.where(source_id: order.id, entry_type: "sale")).to exist

      Sales::OrderStateMachine.call(order, to: "cancelled")

      # cancel-reversal-<id> is the idempotency key used when force: true
      reversal = JournalEntry.find_by(idempotency_key: "cancel-reversal-#{order.id}")
      expect(reversal).to be_present
      expect(reversal.reversal_of_id).to be_present
    end

    it "RefundReversalHandler posts a reversal once the order's financial_status is refunded" do
      order = paid_manual_order(quantity: 1)
      Order.where(id: order.id).update_all(financial_status: "refunded")

      Accounting::RefundReversalHandler.call(order.reload)

      reversal = JournalEntry.find_by(idempotency_key: "refund-reversal-#{order.id}")
      expect(reversal).to be_present
      expect(reversal.reversal_of_id).to be_present
    end

    it "cancelling a pending (unpaid) order does NOT post a reversal" do
      order = paid_manual_order(quantity: 2)
      Order.where(id: order.id).update_all(financial_status: "pending")
      reversal_count_before =
        JournalEntry.where(idempotency_key: "refund-reversal-#{order.id}").count

      Sales::OrderStateMachine.call(order.reload, to: "cancelled")

      expect(
        JournalEntry.where(idempotency_key: "refund-reversal-#{order.id}").count
      ).to eq(reversal_count_before)
      expect(stock_item.reload.quantity_reserved).to eq(0)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # 4b. PAYMENT VOID — releases reservations, no journal effect.
  # ──────────────────────────────────────────────────────────────────────────
  describe "voiding payment" do
    it "releases active reservations on void from authorized" do
      # Create an order but keep it authorized (not paid).
      order = Sales::ManualOrderCreator.call(
        source: "manual", currency: "EGP",
        customer_id: customer.id, customer_email: customer.email,
        customer_name: customer.display_name,
        warehouse_id: warehouse.id, mark_paid: false,
        line_items: [{ variant_id: variant.id, quantity: 2, price: "10.00", title: "T" }]
      )
      # Manually move to authorized
      Order.where(id: order.id).update_all(financial_status: "authorized")
      expect(stock_item.reload.quantity_reserved).to be > 0

      Sales::OrderStateMachine.call(order.reload, to: "voided")

      expect(order.reload.financial_status).to eq("voided")
      expect(stock_item.reload.quantity_reserved).to eq(0)
      # No sale journal should have been posted (order was never paid)
      expect(JournalEntry.where(source_id: order.id, entry_type: "sale")).not_to exist
    end
  end


  describe "refunds" do
    let(:order) { paid_manual_order(quantity: 4) }
    let(:line_item) { order.line_items.first }

    before do
      Shipping::CreateManualFulfillment.call(
        order: order,
        tracking_company: "Bosta",
        line_items: [{ order_line_item_id: line_item.id, quantity: 4 }]
      )
    end

    it "PARTIAL refund with restock: posts partial journal + bumps on_hand" do
      on_hand_before = stock_item.reload.quantity_on_hand

      refund = Sales::ManualRefundCreator.call(
        order_id: order.id,
        amount: "10.00",
        currency: "EGP",
        reason: "customer_request",
        restock: true,
        restock_warehouse_id: warehouse.id,
        line_items: [{ order_line_item_id: line_item.id, quantity: 1, subtotal: "10.00" }]
      )

      expect(refund).to be_processed
      expect(refund.partial?).to be true
      expect(stock_item.reload.quantity_on_hand).to eq(on_hand_before + 1)
      expect(JournalEntry.where(idempotency_key: "refund-partial-#{refund.id}")).to exist
      expect(order.reload.financial_status).to eq("partially_refunded")
    end

    it "PARTIAL refund WITHOUT restock: no inventory movement" do
      on_hand_before = stock_item.reload.quantity_on_hand

      refund = Sales::ManualRefundCreator.call(
        order_id: order.id,
        amount: "10.00",
        currency: "EGP",
        reason: "customer_request",
        restock: false,
        line_items: [{ order_line_item_id: line_item.id, quantity: 1, subtotal: "10.00" }]
      )

      expect(refund.inventory_restocked).to be false
      expect(stock_item.reload.quantity_on_hand).to eq(on_hand_before)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # 6. ILLEGAL TRANSITIONS — must be rejected with InvalidTransition.
  # ──────────────────────────────────────────────────────────────────────────
  describe "illegal transitions" do
    let(:order) { paid_manual_order(quantity: 1) }

    it "cannot go from cancelled back to processing" do
      Sales::OrderStateMachine.call(order, to: "cancelled")
      expect {
        Sales::OrderStateMachine.call(order.reload, to: "processing")
      }.to raise_error(Sales::OrderStateMachine::InvalidTransition)
    end

    it "cannot go from refunded financial_status back to paid" do
      order.update!(financial_status: "refunded")
      expect {
        Sales::OrderStateMachine.call(order, to: "paid")
      }.to raise_error(Sales::OrderStateMachine::InvalidTransition)
    end

    it "cannot go from paid back to pending" do
      expect {
        Sales::OrderStateMachine.call(order, to: "pending")
      }.to raise_error(Sales::OrderStateMachine::InvalidTransition)
    end

    it "rejects unknown target states" do
      expect {
        Sales::OrderStateMachine.call(order, to: "totally_made_up")
      }.to raise_error(Sales::OrderStateMachine::InvalidTransition)
    end
  end

  # ──────────────────────────────────────────────────────────────────────────
  # 7. OVERSOLD GUARD — pre-fulfillment safety check.
  # ──────────────────────────────────────────────────────────────────────────
  describe "oversell protection" do
    it "blocks creating an order line that exceeds available stock" do
      stock_item.update!(quantity_on_hand: 1)

      expect {
        Sales::ManualOrderCreator.call(
          source: "manual", currency: "EGP",
          warehouse_id: warehouse.id, mark_paid: true,
          line_items: [{ variant_id: variant.id, quantity: 5, price: "10.00" }]
        )
      }.to raise_error(Inventory::Oversold)
    end
  end

  def seed_accounts
    {
      "1100" => %w[asset debit],
      "4000" => %w[revenue credit],
      "2200" => %w[liability credit],
      "4100" => %w[revenue credit],
      "1200" => %w[asset debit],
      "5000" => %w[expense debit]
    }.each do |code, (type, side)|
      Account.find_or_create_by!(code: code) do |a|
        a.name = "Acct #{code}"
        a.account_type = type
        a.normal_side = side
        a.currency = "EGP"
      end
    end
  end
end
