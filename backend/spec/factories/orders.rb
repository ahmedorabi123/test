FactoryBot.define do
  factory :order do
    sequence(:order_number) { |n| "SO-202604-#{n.to_s.rjust(4, '0')}" }
    source            { "manual" }
    status            { "pending" }
    financial_status  { "pending" }
    currency          { "USD" }
    subtotal_price    { 100.00 }
    total_tax         { 8.00 }
    total_shipping    { 5.00 }
    total_discount    { 0.00 }
    total_price       { 113.00 }
    customer_email    { "buyer@example.com" }
    customer_name     { "Jane Buyer" }
    placed_at         { Time.current }

    trait :from_shopify do
      source { "shopify" }
      sequence(:shopify_order_id) { |n| 7_000_000 + n }
      sequence(:external_number)  { |n| "##{1000 + n}" }
      shopify_updated_at { Time.current }
    end

    trait :fulfilled do
      status { "fulfilled" }
      financial_status { "paid" }
      fulfillment_status { "fulfilled" }
    end

    trait :cancelled do
      status { "cancelled" }
      cancelled_at { Time.current }
    end

    trait :with_line_items do
      after(:create) do |order|
        create_list(:order_line_item, 2, order: order)
      end
    end
  end

  factory :order_line_item do
    association :order
    sequence(:sku) { |n| "SKU-#{n}" }
    title          { "Sample Item" }
    variant_title  { "Default" }
    quantity       { 2 }
    price          { 25.00 }
    total_discount { 0.00 }
    total_tax      { 0.00 }
    line_total     { 50.00 }
  end
end
