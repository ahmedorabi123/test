require "rails_helper"

RSpec.describe Crm::CustomerStatsRecomputer do
  it "counts placed non-cancelled orders and sums paid-like orders" do
    customer = create(:customer, orders_count: 0, total_spent: 0)
    paid = create(:order, customer: customer, status: "fulfilled", financial_status: "paid", total_price: 120, placed_at: 3.days.ago)
    pending = create(:order, customer: customer, status: "pending", financial_status: "pending", total_price: 80, placed_at: 2.days.ago)
    create(:order, customer: customer, status: "cancelled", financial_status: "voided", total_price: 50, placed_at: 1.day.ago)

    described_class.call(customer)

    expect(customer.reload.orders_count).to eq(2)
    expect(customer.total_spent).to eq(paid.total_price)
    expect(customer.last_order_name).to eq(pending.order_number)
    expect(customer.last_order_at.to_i).to eq(pending.placed_at.to_i)
  end

  it "keeps legitimate zero-order customers at zero" do
    customer = create(:customer, orders_count: 9, total_spent: 99)

    described_class.call(customer)

    expect(customer.reload.orders_count).to eq(0)
    expect(customer.total_spent).to eq(0)
    expect(customer.last_order_name).to be_nil
    expect(customer.last_order_at).to be_nil
  end
end