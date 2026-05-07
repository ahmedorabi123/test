require "rails_helper"

RSpec.describe "Api::V1::Orders timeline", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:order) { create(:order) }

  it "returns order events, fulfillment activity, shipment events, and refunds chronologically" do
    DomainEvent.create!(
      aggregate_type: "Order",
      aggregate_id:   order.id,
      event_type:     "order.created",
      payload:        { source: order.source },
      occurred_at:    4.hours.ago
    )
    fulfillment = create(
      :fulfillment,
      order: order,
      delivery_status: "in_transit",
      created_at: 3.hours.ago,
      updated_at: 3.hours.ago
    )
    ShipmentEvent.create!(
      fulfillment: fulfillment,
      kind: "tracking_update",
      payload: { delivery_status: "out_for_delivery" },
      created_at: 2.hours.ago,
      updated_at: 2.hours.ago
    )
    create(:refund, order: order, amount: "5.00", currency: "EGP", processed_at: 1.hour.ago)

    get "/api/v1/orders/#{order.id}/timeline", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    types = json_response[:data].map { |entry| entry[:type] }
    expect(types).to eq([
      "order.created",
      "fulfillment.created",
      "shipment.tracking_update",
      "refund.processed"
    ])
  end
end
