FactoryBot.define do
  factory :supplier do
    sequence(:name) { |n| "Supplier #{n}" }
    email           { "orders@supplier.test" }
    currency        { "USD" }
    status          { "active" }
  end

  factory :purchase_order do
    supplier
    warehouse { Warehouse.first || create(:warehouse) }
    currency  { "USD" }
    status    { "draft" }
  end

  factory :purchase_order_line_item do
    purchase_order
    variant { Variant.first || create(:variant) }
    title            { "Item" }
    quantity_ordered { 10 }
    quantity_received { 0 }
    unit_cost        { 5.00 }
    subtotal         { 50.00 }
  end
end
