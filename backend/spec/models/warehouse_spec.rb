require "rails_helper"

RSpec.describe Warehouse, type: :model do
  it "upcases code before validation" do
    w = build(:warehouse, code: "wh-ny-01")
    w.valid?
    expect(w.code).to eq("WH-NY-01")
  end

  it "validates code format" do
    expect(build(:warehouse, code: "not valid!")).not_to be_valid
    expect(build(:warehouse, code: "WH-VALID-01")).to be_valid
  end

  it "validates code uniqueness case-insensitively" do
    create(:warehouse, code: "WH-A")
    expect(build(:warehouse, code: "wh-a")).not_to be_valid
  end

  it "validates name presence" do
    expect(build(:warehouse, name: "")).not_to be_valid
  end

  it "active scope filters" do
    create(:warehouse, active: true)
    create(:warehouse, active: false)
    expect(Warehouse.active.count).to eq(1)
  end
end
