require "rails_helper"

RSpec.describe ShipmentEvent, type: :model do
  let(:fulfillment) { create(:fulfillment) }

  it "requires kind" do
    e = ShipmentEvent.new(fulfillment: fulfillment, kind: nil)
    expect(e).not_to be_valid
    expect(e.errors[:kind]).to be_present
  end

  it "is valid with kind only" do
    e = ShipmentEvent.new(fulfillment: fulfillment, kind: "in_transit")
    expect(e).to be_valid
  end

  it "belongs to fulfillment" do
    e = create(:shipment_event_for_spec, fulfillment: fulfillment)
    expect(e.fulfillment).to eq(fulfillment)
  end

  it "actor is optional" do
    e = create(:shipment_event_for_spec, fulfillment: fulfillment, actor: nil)
    expect(e.actor).to be_nil
  end
end

# Inline factory so the spec is self-contained.
FactoryBot.define do
  factory :shipment_event_for_spec, class: "ShipmentEvent" do
    association :fulfillment
    kind { "in_transit" }
  end
end
