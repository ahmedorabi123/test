FactoryBot.define do
  factory :warehouse do
    sequence(:name) { |n| "Warehouse #{n}" }
    sequence(:code) { |n| "WH-#{n.to_s.rjust(3, '0')}" }
    active { true }
  end

  factory :stock_item do
    association :variant
    association :warehouse
    quantity_on_hand  { 10 }
    quantity_reserved { 0 }
    low_stock_threshold { 5 }
  end

  factory :stock_movement do
    association :stock_item
    delta           { 5 }
    reason          { "received" }
    snapshot_before { 0 }
    snapshot_after  { 5 }
  end
end
