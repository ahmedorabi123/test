require "rails_helper"

RSpec.describe Shopify::Reconcile::MissingChildren do
  it "fetches Shopify orders missing local fulfillments" do
    fulfillment_order = create(:order, :from_shopify, :fulfilled, shopify_order_id: 101)
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
    allow(Shipping::Shopify::FulfillmentUpserter).to receive(:call)

    result = described_class.call(client: client, log: ->(_message) {})

    expect(result).to eq(fulfillments: 1)
    expect(Shipping::Shopify::FulfillmentUpserter).to have_received(:call).with(
      { "id" => 5, "order_id" => fulfillment_order.shopify_order_id }
    )
  end
end
