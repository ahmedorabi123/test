require "rails_helper"

RSpec.describe Crm::Shopify::CustomerUpserter do
  let(:payload) do
    {
      "id"            => 555_555,
      "email"         => "new@buyer.com",
      "phone"         => "+20100000000",
      "first_name"    => "Ahmed",
      "last_name"     => "Mostafa",
      "tags"          => "vip, shopify",
      "default_address" => { "city" => "Cairo", "country" => "EG" },
      "orders_count"  => 3,
      "total_spent"   => "450.00",
      "currency"      => "EGP",
      "updated_at"    => "2026-04-22T10:00:00Z"
    }
  end

  it "creates a customer with normalized tags" do
    expect {
      described_class.call(payload)
    }.to change(Customer, :count).by(1)

    c = Customer.last
    expect(c.shopify_customer_id.to_i).to eq(555_555)
    expect(c.email).to eq("new@buyer.com")
    expect(c.full_name).to eq("Ahmed Mostafa")
    expect(c.tags).to eq(["vip", "shopify"])
    expect(c.orders_count).to eq(3)
  end

  it "is idempotent and updates in place" do
    described_class.call(payload)
    payload["first_name"] = "Ahmed Updated"
    payload["updated_at"] = "2026-04-23T10:00:00Z"
    expect {
      described_class.call(payload)
    }.not_to change(Customer, :count)
    expect(Customer.last.first_name).to eq("Ahmed Updated")
  end

  it "back-links existing orders that had only shopify_customer_id" do
    order = create(:order, :from_shopify, shopify_customer_id: 555_555, customer_id: nil)
    described_class.call(payload)
    expect(order.reload.customer).to eq(Customer.last)
  end

  it "skips overwriting with older payloads" do
    described_class.call(payload)
    older = payload.merge("first_name" => "Stale", "updated_at" => "2026-01-01T00:00:00Z")
    described_class.call(older)
    expect(Customer.last.first_name).to eq("Ahmed")
  end
end
