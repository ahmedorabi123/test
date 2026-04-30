FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@erp.local" }
    password { "password123!" }
    first_name { "Test" }
    last_name  { "User" }
    active     { true }

    trait :admin do
      after(:create) do |user|
        role = Role.find_or_create_by!(name: "admin")
        user.roles << role unless user.roles.include?(role)
      end
    end

    trait :inactive do
      active { false }
    end
  end

  factory :role do
    sequence(:name) { |n| "role_#{n}" }
    description { "Generated role" }
  end

  factory :permission do
    sequence(:resource) { |n| "resource_#{n}" }
    action { "read" }
  end
end
