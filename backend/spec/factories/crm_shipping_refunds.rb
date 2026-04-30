FactoryBot.define do
  factory :customer do
    sequence(:email) { |n| "customer#{n}@example.com" }
    first_name { "Jane" }
    last_name  { "Doe" }
    phone      { "+1-555-0100" }
    currency   { "USD" }
    tags       { [] }
  end

  factory :fulfillment do
    association :order
    status           { "success" }
    tracking_company { "Bosta" }
    sequence(:tracking_number) { |n| "BST-#{n}" }
    shipped_at       { Time.current }
  end

  factory :refund do
    association :order
    amount   { 10.00 }
    currency { "USD" }
    reason   { "customer_request" }
    restock  { false }
    processed_at { Time.current }
  end
end
