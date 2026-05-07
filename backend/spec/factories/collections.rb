FactoryBot.define do
  factory :collection do
    sequence(:title)  { |n| "Collection #{n}" }
    sequence(:handle) { |n| "collection-#{n}" }
    kind { "custom" }
    published_scope { "web" }

    trait :smart do
      kind { "smart" }
      rules { [{ "column" => "title", "relation" => "contains", "condition" => "shirt" }] }
      disjunctive { false }
    end

    trait :published do
      published_at { 1.day.ago }
    end

    trait :from_shopify do
      sequence(:shopify_collection_id) { |n| 2_000_000 + n }
      shopify_updated_at { Time.current }
    end
  end
end
