require "rails_helper"

RSpec.describe "Order#last_delivery_status pipeline", type: :model do
  let(:order) { create(:order) }

  it "is set when a manual fulfillment is created" do
    order_line_item = create(:order_line_item, order: order, quantity: 1, fulfilled_quantity: 0)

    Shipping::CreateManualFulfillment.call(
      order:            order,
      tracking_company: "Manual",
      tracking_number:  "TN-1",
      line_items:       [ { order_line_item_id: order_line_item.id, quantity: 1 } ],
      transition_order: false
    )

    expect(order.reload.last_delivery_status).to eq("pending")
  end

  it "is updated when a fulfillment's delivery_status changes" do
    fulfillment = Fulfillment.create!(
      order:            order,
      status:           "success",
      delivery_status:  "pending",
      tracking_company: "Bosta",
      tracking_number:  "BST-1"
    )
    expect(order.reload.last_delivery_status).to eq("pending")

    fulfillment.update!(delivery_status: "in_transit")
    expect(order.reload.last_delivery_status).to eq("in_transit")

    fulfillment.update!(delivery_status: "delivered")
    expect(order.reload.last_delivery_status).to eq("delivered")
  end

  it "uses the most recent fulfillment when multiple exist" do
    Fulfillment.create!(
      order: order, status: "success", delivery_status: "delivered",
      tracking_company: "A", created_at: 2.days.ago
    )
    Fulfillment.create!(
      order: order, status: "success", delivery_status: "in_transit",
      tracking_company: "B", created_at: 1.day.ago
    )
    expect(order.reload.last_delivery_status).to eq("in_transit")
  end
end
