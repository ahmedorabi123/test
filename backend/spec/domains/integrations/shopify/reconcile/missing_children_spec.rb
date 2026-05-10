require "rails_helper"

RSpec.describe Shopify::Reconcile::MissingChildren do
  it "fetches Shopify orders missing local fulfillments and refunds" do
    fulfillment_order = create(:order, :from_shopify, :fulfilled, shopify_order_id: 101)
    refund_order = create(:order, :from_shopify, financial_status: "partially_refunded", shopify_order_id: 202)
    create(:fulfillment, order: create(:order, :from_shopify, :fulfilled, shopify_order_id: 303))

    client = instance_double(Shopify::Client)
    allow(client).to receive(:get).with(
      "orders.json",
      params: { ids: fulfillment_order.shopify_order_id.to_s, limit: 250, status: "any" }
    ).and_return(
      "orders" => [
        {
          "id" => fulfillment_order.shopify_order_id,
          "fulfillments" => [{ "id" => 5 }],
          "refunds" => []
        }
      ]
    )
    allow(client).to receive(:get).with(
      "orders.json",
      params: { ids: refund_order.shopify_order_id.to_s, limit: 250, status: "any" }
    ).and_return(
      "orders" => [
        {
          "id" => refund_order.shopify_order_id,
          "fulfillments" => [],
          "refunds" => [{ "id" => 9, "order_id" => refund_order.shopify_order_id }]
        }
      ]
    )

    allow(Shipping::Shopify::FulfillmentUpserter).to receive(:call)
    allow(Sales::Shopify::RefundUpserter).to receive(:call)

    result = described_class.call(client: client, log: ->(_message) {})

    expect(result).to eq(fulfillments: 1, refunds: 1)
    expect(Shipping::Shopify::FulfillmentUpserter).to have_received(:call).with(
      { "id" => 5, "order_id" => fulfillment_order.shopify_order_id }
    )
    expect(Sales::Shopify::RefundUpserter).to have_received(:call).with(
      { "id" => 9, "order_id" => refund_order.shopify_order_id }
    )
  end
end
