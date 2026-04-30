FactoryBot.define do
  factory :account do
    sequence(:code) { |n| (1000 + n).to_s }
    name         { "Test Account #{code}" }
    account_type { "asset" }
    normal_side  { "debit" }
    currency     { "EGP" }
    active       { true }
  end
end
