require "rails_helper"

RSpec.describe "Manual and showroom inventory lifecycle", type: :model do
  let(:warehouse) { create(:warehouse, code: "WH-MAIN", active: true) }
  let(:transfer_warehouse) { create(:warehouse, code: "WH-SECOND", active: true) }
  let(:product) { create(:product) }
  let(:variant) { create(:variant, product: product, sku: "LIFE-SKU", price: "10.00") }
  let!(:stock_item) { create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 10) }

  before { seed_accounts }

  it "reserves, protects, fulfills, and refunds manual orders consistently" do
    order = Sales::ManualOrderCreator.call(
      source: "manual",
      currency: "EGP",
      customer_email: "manual@example.com",
      customer_name: "Manual Buyer",
      warehouse_id: warehouse.id,
      mark_paid: true,
      line_items: [
        { variant_id: variant.id, quantity: 3, price: "10.00", title: "Lifecycle Item" }
      ]
    )

    line_item = order.line_items.first
    expect(order.financial_status).to eq("paid")
    expect(stock_item.reload.quantity_reserved).to eq(3)
    expect(line_item.stock_reservations.active.sum(:quantity)).to eq(3)

    expect {
      Inventory::TransferStock.call(
        variant: variant,
        from_warehouse: warehouse,
        to_warehouse: transfer_warehouse,
        quantity: 8
      )
    }.to raise_error(Inventory::TransferStock::InsufficientStock, /only 7 available/)

    fulfillment = Shipping::CreateManualFulfillment.call(
      order: order,
      tracking_company: "Manual",
      line_items: [ { order_line_item_id: line_item.id, quantity: 2 } ]
    )

    expect(fulfillment.fulfillment_line_items.count).to eq(1)
    expect(stock_item.reload.quantity_on_hand).to eq(8)
    expect(stock_item.quantity_reserved).to eq(1)
    expect(line_item.reload.fulfilled_quantity).to eq(2)
    expect(order.reload.fulfillment_status).to eq("partial")

    refund = Sales::ManualRefundCreator.call(
      order_id: order.id,
      amount: "10.00",
      currency: "EGP",
      reason: "customer_request",
      restock: true,
      restock_warehouse_id: warehouse.id,
      line_items: [ { order_line_item_id: line_item.id, quantity: 1, subtotal: "10.00" } ]
    )

    expect(refund).to be_processed
    expect(refund).to be_inventory_restocked
    expect(stock_item.reload.quantity_on_hand).to eq(9)
    expect(order.reload.financial_status).to eq("partially_refunded")
    expect(JournalEntry.where(idempotency_key: "refund-partial-#{refund.id}")).to exist
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
      Account.find_or_create_by!(code: code) do |account|
        account.name = "Account #{code}"
        account.account_type = type
        account.normal_side = side
        account.currency = "EGP"
      end
    end
  end
end
