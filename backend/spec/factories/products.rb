FactoryBot.define do
  factory :product do
    sequence(:title)  { |n| "Product #{n}" }
    sequence(:handle) { |n| "product-#{n}" }
    status { "active" }
    vendor { "ACME" }
    product_type { "Apparel" }

    trait :with_variant do
      after(:create) do |product|
        create(:variant, product: product)
      end
    end

    trait :from_shopify do
      sequence(:shopify_product_id) { |n| 1_000_000 + n }
      shopify_updated_at { Time.current }
    end
  end

  factory :variant do
    association :product
    sequence(:sku) { |n| "SKU-#{n}" }
    title { "Default Title" }
    price { 19.99 }
    position { 1 }

    trait :from_shopify do
      sequence(:shopify_variant_id) { |n| 2_000_000 + n }
      sequence(:shopify_inventory_item_id) { |n| 3_000_000 + n }
    end
  end
end
