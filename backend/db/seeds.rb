# Seeds are idempotent — safe to run multiple times.

# ─────────────────────────────────────────────────────────────────────────────
# 1. Permissions & Roles
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Permissions =="
Permission::ALL.each do |key|
  resource, action = key.split(":")
  Permission.find_or_create_by!(resource: resource, action: action)
end
puts "   #{Permission.count} permissions"

puts "== Seeding Roles =="
all_permissions = Permission.all.to_a

admin_role = Role.find_or_create_by!(name: "admin") do |r|
  r.description = "Full access to all modules"
end
admin_role.permissions = all_permissions

operations_role = Role.find_or_create_by!(name: "operations") do |r|
  r.description = "Manage orders, fulfillments, inventory"
end
operations_perms = Permission.where(
  resource: %w[orders fulfillments customers products inventory stock_transfers warehouses]
)
operations_role.permissions = operations_perms

showroom_role = Role.find_or_create_by!(name: "showroom_clerk") do |r|
  r.description = "Create showroom orders and view stock"
end
showroom_perms = Permission.where(resource: %w[orders customers inventory]).where(action: %w[read write])
showroom_role.permissions = showroom_perms

accountant_role = Role.find_or_create_by!(name: "accountant") do |r|
  r.description = "View and post accounting entries"
end
accountant_perms = Permission.where(resource: %w[accounting orders fulfillments customers])
accountant_role.permissions = accountant_perms

viewer_role = Role.find_or_create_by!(name: "viewer") do |r|
  r.description = "Read-only access to all modules"
end
viewer_perms = Permission.where(action: "read")
viewer_role.permissions = viewer_perms

puts "   #{Role.count} roles seeded"

# ─────────────────────────────────────────────────────────────────────────────
# 2. Users (all with permanent passwords — no expiry)
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Users =="
admin_email    = ENV.fetch("ADMIN_EMAIL",    "admin@erp.local")
admin_password = ENV.fetch("ADMIN_PASSWORD", "changeme123!")

seed_users = [
  { email: admin_email,            password: admin_password,  first_name: "ERP",    last_name: "Admin",   role: admin_role },
  { email: "ops@erp.local",        password: "changeme123!",  first_name: "Oliver", last_name: "Ops",     role: operations_role },
  { email: "viewer@erp.local",     password: "changeme123!",  first_name: "Vera",   last_name: "Viewer",  role: viewer_role },
  { email: "accountant@erp.local", password: "changeme123!",  first_name: "Alan",   last_name: "Counts",  role: accountant_role },
]

seed_users.each do |attrs|
  u = User.find_or_initialize_by(email: attrs[:email])
  u.assign_attributes(
    first_name: attrs[:first_name],
    last_name:  attrs[:last_name],
    password:   attrs[:password],
    active:     true
  )
  u.save!
  u.user_roles.find_or_create_by!(role: attrs[:role])
end

puts "   #{User.count} users seeded"
puts ""
puts "   ┌───────────────────────────────────────────────────────┐"
puts "   │  UI TEST CREDENTIALS (all passwords: changeme123!)    │"
puts "   │  admin@erp.local       → Admin (full access)          │"
puts "   │  ops@erp.local         → Operations                   │"
puts "   │  viewer@erp.local      → Viewer (read-only)           │"
puts "   │  accountant@erp.local  → Accountant                   │"
puts "   └───────────────────────────────────────────────────────┘"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Warehouses
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Warehouses =="
wh_data = [
  { name: "New York — Main DC",      code: "NY-DC-01",  address: "1 Commerce Way, Brooklyn, NY 11201" },
  { name: "Los Angeles — West Coast", code: "LA-DC-01",  address: "500 Warehouse Blvd, Carson, CA 90745" },
  { name: "Chicago — Midwest Hub",    code: "CH-DC-01",  address: "2200 Industrial Dr, Chicago, IL 60601" },
  { name: "Showroom — NYC Flagship",  code: "SR-NYC-01", address: "155 Spring St, New York, NY 10012", kind: "consignment", partner_name: "Flagship NYC Partners" },
  { name: "Showroom — LA Downtown",   code: "SR-LA-01",  address: "801 S Broadway, Los Angeles, CA 90014", kind: "consignment", partner_name: "Downtown LA Retailers" },
]
warehouses = wh_data.map do |attrs|
  Warehouse.find_or_create_by!(code: attrs[:code]) do |w|
    w.name         = attrs[:name]
    w.address      = attrs[:address]
    w.active       = attrs.fetch(:active, true)
    w.kind         = attrs.fetch(:kind, "own")
    w.partner_name = attrs[:partner_name]
  end
end
puts "   #{Warehouse.count} warehouses"

# ─────────────────────────────────────────────────────────────────────────────
# 4. Products & Variants
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Products =="

catalog = [
  {
    title: "Classic Crew-Neck Tee",
    handle: "classic-crew-neck-tee",
    status: "active",
    vendor: "ACME Apparel",
    product_type: "T-Shirts",
    description: "<p>A timeless staple in 100% organic cotton.</p>",
    variants: [
      { sku: "TEE-BLK-XS", title: "Black / XS",  price: "24.99", compare_at_price: "34.99", position: 1 },
      { sku: "TEE-BLK-S",  title: "Black / S",   price: "24.99", compare_at_price: "34.99", position: 2 },
      { sku: "TEE-BLK-M",  title: "Black / M",   price: "24.99", compare_at_price: "34.99", position: 3 },
      { sku: "TEE-BLK-L",  title: "Black / L",   price: "24.99", compare_at_price: "34.99", position: 4 },
      { sku: "TEE-WHT-S",  title: "White / S",   price: "24.99", compare_at_price: "34.99", position: 5 },
      { sku: "TEE-WHT-M",  title: "White / M",   price: "24.99", compare_at_price: "34.99", position: 6 },
    ],
  },
  {
    title: "Slim-Fit Chinos",
    handle: "slim-fit-chinos",
    status: "active",
    vendor: "ACME Apparel",
    product_type: "Pants",
    description: "<p>Smart casual chinos in stretch cotton-blend.</p>",
    variants: [
      { sku: "CHN-KHK-30",  title: "Khaki / 30×30", price: "59.00", position: 1 },
      { sku: "CHN-KHK-32",  title: "Khaki / 32×30", price: "59.00", position: 2 },
      { sku: "CHN-NAV-30",  title: "Navy / 30×30",  price: "59.00", position: 3 },
      { sku: "CHN-NAV-32",  title: "Navy / 32×30",  price: "59.00", position: 4 },
    ],
  },
  {
    title: "Leather Sneakers",
    handle: "leather-sneakers",
    status: "active",
    vendor: "SoleCraft",
    product_type: "Footwear",
    description: "<p>Italian leather uppers with cushioned insoles.</p>",
    variants: [
      { sku: "SHO-WHT-40", title: "White / EU 40", price: "129.00", compare_at_price: "159.00", position: 1 },
      { sku: "SHO-WHT-41", title: "White / EU 41", price: "129.00", compare_at_price: "159.00", position: 2 },
      { sku: "SHO-WHT-42", title: "White / EU 42", price: "129.00", compare_at_price: "159.00", position: 3 },
      { sku: "SHO-BLK-41", title: "Black / EU 41", price: "129.00", compare_at_price: "159.00", position: 4 },
    ],
  },
  {
    title: "Canvas Tote Bag",
    handle: "canvas-tote-bag",
    status: "active",
    vendor: "CarryOn",
    product_type: "Accessories",
    description: "<p>Heavy-duty 12oz canvas with reinforced straps.</p>",
    variants: [
      { sku: "TOT-NAT-OS", title: "Natural / One Size", price: "19.99", position: 1 },
      { sku: "TOT-BLK-OS", title: "Black / One Size",   price: "19.99", position: 2 },
    ],
  },
  {
    title: "Merino Wool Beanie",
    handle: "merino-wool-beanie",
    status: "active",
    vendor: "ACME Apparel",
    product_type: "Accessories",
    description: "<p>100% merino wool beanie — warm but not scratchy.</p>",
    variants: [
      { sku: "BNE-GRY-OS", title: "Grey / One Size",  price: "29.00", position: 1 },
      { sku: "BNE-NVY-OS", title: "Navy / One Size",  price: "29.00", position: 2 },
      { sku: "BNE-RED-OS", title: "Red / One Size",   price: "29.00", position: 3 },
    ],
  },
  {
    title: "Running Shorts (Draft)",
    handle: "running-shorts-draft",
    status: "draft",
    vendor: "SportMax",
    product_type: "Activewear",
    description: "<p>Not yet published. Work in progress.</p>",
    variants: [
      { sku: "SHT-BLK-S", title: "Black / S", price: "34.99", position: 1 },
    ],
  },
  {
    title: "Puffer Jacket (Archived)",
    handle: "puffer-jacket-archived",
    status: "archived",
    vendor: "ACME Apparel",
    product_type: "Outerwear",
    description: "<p>Previous season — archived.</p>",
    variants: [
      { sku: "PFR-BLK-M", title: "Black / M", price: "199.00", position: 1 },
    ],
  },
]

all_products = catalog.map do |p_attrs|
  product = Product.find_or_create_by!(handle: p_attrs[:handle]) do |p|
    p.title        = p_attrs[:title]
    p.status       = p_attrs[:status]
    p.vendor       = p_attrs[:vendor]
    p.product_type = p_attrs[:product_type]
    p.description  = p_attrs[:description]
  end
  # Update mutable fields on re-seed
  product.update!(
    title:        p_attrs[:title],
    status:       p_attrs[:status],
    vendor:       p_attrs[:vendor],
    product_type: p_attrs[:product_type],
    description:  p_attrs[:description]
  )
  p_attrs[:variants].each do |v_attrs|
    v = Variant.find_or_create_by!(sku: v_attrs[:sku], product: product) do |v|
      v.title            = v_attrs[:title]
      v.price            = v_attrs[:price]
      v.compare_at_price = v_attrs[:compare_at_price]
      v.position         = v_attrs[:position]
    end
    v.update!(
      title:            v_attrs[:title],
      price:            v_attrs[:price],
      compare_at_price: v_attrs[:compare_at_price],
      position:         v_attrs[:position]
    )
  end
  product
end

puts "   #{Product.count} products / #{Variant.count} variants seeded"

# ─────────────────────────────────────────────────────────────────────────────
# 5. Stock Items (variant × warehouse)
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Stock Items =="

ny_wh  = warehouses[0]
la_wh  = warehouses[1]
chi_wh = warehouses[2]

# Stock levels per warehouse (variant index → qty)
stock_config = [
  # [warehouse, [qty per variant in each product's variants array]]
  [ny_wh,  { "TEE-BLK-XS" => 120, "TEE-BLK-S" => 85, "TEE-BLK-M" => 3,  "TEE-BLK-L" => 50,
             "TEE-WHT-S"  => 200, "TEE-WHT-M" => 165,
             "CHN-KHK-30" => 40,  "CHN-KHK-32" => 28, "CHN-NAV-30" => 12, "CHN-NAV-32" => 4,
             "SHO-WHT-40" => 15,  "SHO-WHT-41" => 10, "SHO-WHT-42" => 2,  "SHO-BLK-41" => 8,
             "TOT-NAT-OS" => 300, "TOT-BLK-OS" => 280,
             "BNE-GRY-OS" => 90,  "BNE-NVY-OS" => 3,  "BNE-RED-OS" => 60 }],
  [la_wh,  { "TEE-BLK-S" => 30, "TEE-BLK-M" => 20, "TEE-WHT-M" => 45,
             "SHO-WHT-41" => 5,  "SHO-WHT-42" => 1,
             "TOT-NAT-OS" => 150, "TOT-BLK-OS" => 120,
             "BNE-GRY-OS" => 25, "BNE-NVY-OS" => 4 }],
  [chi_wh, { "TEE-BLK-M" => 60, "TEE-WHT-M" => 55,
             "CHN-KHK-32" => 20, "CHN-NAV-32" => 15,
             "BNE-GRY-OS" => 10, "BNE-RED-OS" => 35 }],
]

stock_config.each do |warehouse, sku_qty|
  sku_qty.each do |sku, qty|
    variant = Variant.find_by(sku: sku)
    next unless variant
    si = StockItem.find_or_initialize_by(variant: variant, warehouse: warehouse)
    si.quantity_on_hand  = qty
    si.low_stock_threshold = 5
    si.save!
  end
end

puts "   #{StockItem.count} stock items seeded"
puts "   Low-stock items: #{StockItem.low_stock.count} (available ≤ threshold)"

# ─────────────────────────────────────────────────────────────────────────────
# 6. Sales — Orders (demo data spanning statuses + date range)
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Orders =="

demo_orders = [
  { num: "SO-202604-0001", email: "emma.stone@example.com",  name: "Emma Stone",
    status: "fulfilled",  fin: "paid",            fs: "fulfilled",
    placed_at: 25.days.ago, lines: [{ sku: "TEE-BLK-M",  qty: 2, price: 24.99 },
                                    { sku: "SHO-WHT-41", qty: 1, price: 129.00 }] },

  { num: "SO-202604-0002", email: "liam.parker@example.com", name: "Liam Parker",
    status: "fulfilled",  fin: "paid",            fs: "fulfilled",
    placed_at: 18.days.ago, lines: [{ sku: "CHN-KHK-32", qty: 1, price: 59.00 },
                                    { sku: "BNE-GRY-OS", qty: 2, price: 29.00 }] },

  { num: "SO-202604-0003", email: "sophia.chen@example.com", name: "Sophia Chen",
    status: "processing", fin: "paid",            fs: "partial",
    placed_at: 6.days.ago,  lines: [{ sku: "TOT-BLK-OS", qty: 3, price: 19.99 },
                                    { sku: "TEE-WHT-M",  qty: 2, price: 24.99 }] },

  { num: "SO-202604-0004", email: "noah.kim@example.com",    name: "Noah Kim",
    status: "pending",    fin: "pending",         fs: nil,
    placed_at: 3.days.ago,  lines: [{ sku: "SHO-BLK-41", qty: 1, price: 129.00 }] },

  { num: "SO-202604-0005", email: "olivia.may@example.com",  name: "Olivia May",
    status: "pending",    fin: "authorized",      fs: nil,
    placed_at: 1.day.ago,   lines: [{ sku: "TEE-BLK-S",  qty: 1, price: 24.99 },
                                    { sku: "BNE-NVY-OS", qty: 1, price: 29.00 }] },

  { num: "SO-202604-0006", email: "ava.brown@example.com",   name: "Ava Brown",
    status: "cancelled",  fin: "voided",          fs: nil,
    placed_at: 9.days.ago, cancelled_at: 8.days.ago,
    lines: [{ sku: "CHN-NAV-32", qty: 1, price: 59.00 }] },

  { num: "SO-202604-0007", email: "mason.reyes@example.com", name: "Mason Reyes",
    status: "refunded",   fin: "refunded",        fs: "fulfilled",
    placed_at: 12.days.ago, lines: [{ sku: "SHO-WHT-42", qty: 1, price: 129.00 }] },

  { num: "SO-202604-0008", email: "isabella.lee@example.com", name: "Isabella Lee",
    status: "fulfilled",  fin: "paid",            fs: "fulfilled",
    placed_at: 14.days.ago, lines: [{ sku: "BNE-RED-OS", qty: 5, price: 29.00 }] },
]

demo_orders.each do |o|
  order = Order.find_or_initialize_by(order_number: o[:num])
  is_new = order.new_record?

  subtotal = o[:lines].sum { |l| l[:price].to_d * l[:qty] }
  tax      = (subtotal * 0.08).round(2)
  shipping = 5.to_d
  total    = subtotal + tax + shipping

  order.assign_attributes(
    source:             "showroom",
    status:             o[:status],
    financial_status:   o[:fin],
    fulfillment_status: o[:fs],
    currency:           "USD",
    subtotal_price:     subtotal,
    total_tax:          tax,
    total_shipping:     shipping,
    total_discount:     0,
    total_price:        total,
    customer_email:     o[:email],
    customer_name:      o[:name],
    shipping_address:   { "city" => "New York", "country" => "US" },
    billing_address:    { "city" => "New York", "country" => "US" },
    placed_at:          o[:placed_at],
    cancelled_at:       o[:cancelled_at]
  )
  order.save!

  # Only build line items on first seed of this order. On re-seed, fulfillments
  # and refunds may reference these rows (FK constraint), so leave them alone.
  next unless is_new

  o[:lines].each_with_index do |l, _idx|
    variant = Variant.find_by(sku: l[:sku])
    order.line_items.create!(
      variant:        variant,
      sku:            l[:sku],
      title:          variant&.product&.title || "Unknown Product",
      variant_title:  variant&.title,
      quantity:       l[:qty],
      price:          l[:price],
      total_discount: 0,
      total_tax:      (l[:price].to_d * l[:qty] * 0.08).round(2),
      line_total:     l[:price].to_d * l[:qty]
    )
  end
end

puts "   #{Order.count} orders seeded (#{Order.last_30_days.count} in last 30 days)"
puts "   By status: #{Order.group(:status).count}"

# ─────────────────────────────────────────────────────────────────────────────
# 7. Chart of Accounts (EGP — simplified 4-digit COA)
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Chart of Accounts =="

coa = [
  # ── Assets ────────────────────────────────────────────────────────────────
  { code: "1000", name: "Cash & Cash Equivalents",    type: "asset",     side: "debit",  desc: "Cash on hand and bank balances" },
  { code: "1100", name: "Accounts Receivable",        type: "asset",     side: "debit",  desc: "Amounts owed by customers" },
  { code: "1200", name: "Inventory",                  type: "asset",     side: "debit",  desc: "Goods held for sale" },
  { code: "1300", name: "Prepaid Expenses",            type: "asset",     side: "debit",  desc: "Prepaid costs" },
  { code: "1500", name: "Property & Equipment",       type: "asset",     side: "debit",  desc: "Tangible fixed assets" },
  # ── Liabilities ────────────────────────────────────────────────────────────
  { code: "2000", name: "Accounts Payable",           type: "liability", side: "credit", desc: "Amounts owed to suppliers" },
  { code: "2100", name: "Accrued Liabilities",        type: "liability", side: "credit", desc: "Accrued expenses" },
  { code: "2200", name: "Sales Tax Payable",          type: "liability", side: "credit", desc: "VAT / sales tax collected" },
  { code: "2300", name: "Customer Deposits",          type: "liability", side: "credit", desc: "Advance payments from customers" },
  # ── Equity ─────────────────────────────────────────────────────────────────
  { code: "3000", name: "Owner's Equity",             type: "equity",    side: "credit", desc: "Paid-in capital" },
  { code: "3100", name: "Retained Earnings",          type: "equity",    side: "credit", desc: "Cumulative net income" },
  # ── Revenue ────────────────────────────────────────────────────────────────
  { code: "4000", name: "Sales Revenue",              type: "revenue",   side: "credit", desc: "Product sales income" },
  { code: "4100", name: "Shipping Revenue",           type: "revenue",   side: "credit", desc: "Shipping fees charged to customers" },
  { code: "4200", name: "Other Revenue",              type: "revenue",   side: "credit", desc: "Miscellaneous income" },
  # ── Expenses ───────────────────────────────────────────────────────────────
  { code: "5000", name: "Cost of Goods Sold",         type: "expense",   side: "debit",  desc: "Direct cost of products sold" },
  { code: "5100", name: "Shipping & Fulfillment",     type: "expense",   side: "debit",  desc: "Outbound shipping costs" },
  { code: "5200", name: "Returns & Allowances",       type: "expense",   side: "debit",  desc: "Customer returns" },
  { code: "6000", name: "Payroll Expense",            type: "expense",   side: "debit",  desc: "Salaries and wages" },
  { code: "6100", name: "Rent & Occupancy",           type: "expense",   side: "debit",  desc: "Showroom and office rent" },
  { code: "6200", name: "Marketing & Advertising",    type: "expense",   side: "debit",  desc: "Ad spend and promotions" },
  { code: "6300", name: "Technology & Software",      type: "expense",   side: "debit",  desc: "SaaS, hosting, dev tools" },
  { code: "6900", name: "General & Administrative",   type: "expense",   side: "debit",  desc: "Other G&A expenses" },
]

coa.each do |a|
  Account.find_or_create_by!(code: a[:code]) do |acc|
    acc.name         = a[:name]
    acc.account_type = a[:type]
    acc.normal_side  = a[:side]
    acc.description  = a[:desc]
    acc.currency     = "EGP"
    acc.active       = true
  end
end
puts "   #{Account.count} accounts seeded"

# Post journal entries for the 3 'paid' demo orders
puts "== Posting demo journal entries =="
posted = 0
Order.where(financial_status: "paid").each do |o|
  entry = Accounting::PostSaleJournalHandler.call(o)
  posted += 1 if entry
end
# Reverse the refunded order if its sale entry exists
Order.where(financial_status: "refunded").each do |o|
  Accounting::RefundReversalHandler.call(o)
end
puts "   #{posted} sale journal entries posted"
puts "   #{JournalEntry.count} total journal entries"

# ─────────────────────────────────────────────────────────────────────────────
# 8. CRM demo customers
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Customers =="
demo_customers = [
  { email: "emma.stone@example.com",  first: "Emma",  last: "Stone",  phone: "+1-555-0101", tags: ["vip"] },
  { email: "liam.parker@example.com", first: "Liam",  last: "Parker", phone: "+1-555-0102", tags: [] },
  { email: "sophia.chen@example.com", first: "Sophia",last: "Chen",   phone: "+1-555-0103", tags: ["wholesale"] },
]
demo_customers.each do |c|
  customer = Customer.find_or_initialize_by(email: c[:email])
  customer.assign_attributes(
    first_name: c[:first], last_name: c[:last], phone: c[:phone], tags: c[:tags], currency: "USD"
  )
  customer.save!
  # Back-link any order with the same email
  Order.where(customer_email: c[:email], customer_id: nil).update_all(customer_id: customer.id)
end
puts "   #{Customer.count} customers seeded"

# ─────────────────────────────────────────────────────────────────────────────
# 9. Fulfillments (demo shipments through Bosta) for fulfilled orders
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Fulfillments =="
Order.where(fulfillment_status: "fulfilled").each_with_index do |o, idx|
  next if o.fulfillments.any?
  f = o.fulfillments.create!(
    status:           "success",
    tracking_company: "Bosta",
    tracking_number:  "BST-DEMO-#{1000 + idx}",
    tracking_url:     "https://bosta.co/track/BST-DEMO-#{1000 + idx}",
    shipped_at:       o.placed_at + 1.day
  )
  o.line_items.each do |li|
    f.fulfillment_line_items.create!(order_line_item: li, quantity: li.quantity)
  end
end
puts "   #{Fulfillment.count} fulfillments seeded"

# ─────────────────────────────────────────────────────────────────────────────
# 10. Refunds (demo) for refunded order
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Refunds =="
Order.where(financial_status: "refunded").each do |o|
  next if o.refunds.any?
  r = o.refunds.create!(
    amount:       o.total_price,
    currency:     o.currency,
    reason:       "customer_request",
    note:         "Returned via Estebdal",
    restock:      true,
    processed_at: (o.placed_at || 2.days.ago) + 2.days
  )
  o.line_items.each do |li|
    r.refund_line_items.create!(
      order_line_item: li, quantity: li.quantity, subtotal: li.line_total,
      restock: true, restock_type: "return"
    )
  end
end
puts "   #{Refund.count} refunds seeded"

# ─────────────────────────────────────────────────────────────────────────────
# 11. Purchases (suppliers + POs)
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Suppliers =="
acme = Supplier.find_or_create_by!(name: "Acme Textiles") do |s|
  s.email = "orders@acme-textiles.example"
  s.phone = "+20 100 0000 000"
  s.currency = "USD"
  s.status = "active"
  s.payment_terms = { net_days: 30 }
end
globex = Supplier.find_or_create_by!(name: "Globex Apparel") do |s|
  s.email = "sales@globex.example"
  s.currency = "USD"
  s.status = "active"
end
puts "   #{Supplier.count} suppliers seeded"

puts "== Seeding Purchase Orders =="
if PurchaseOrder.count.zero?
  wh = Warehouse.active.first
  variant1, variant2 = Variant.limit(2).to_a
  if wh && variant1
    Purchases::PurchaseOrderCreator.call(
      supplier_id: acme.id,
      warehouse_id: wh.id,
      currency: "USD",
      expected_at: 7.days.from_now,
      notes: "Restock basics",
      line_items: [
        { variant_id: variant1.id, quantity_ordered: 50, unit_cost: variant1.price.to_d * 0.6 },
        ({ variant_id: variant2.id, quantity_ordered: 30, unit_cost: variant2.price.to_d * 0.6 } if variant2)
      ].compact
    )
  end
end
puts "   #{PurchaseOrder.count} purchase orders seeded"

puts ""
puts "========================================================"
puts "  Seed complete — app is ready for UI testing"
puts "========================================================"

# ─────────────────────────────────────────────────────────────────────────────
# Final step: register Shopify webhooks + backfill live Shopify data into DB.
# Self-skipping when DB already has Shopify data (idempotent across redeploys).
# Driven by the same logic as `rails bootstrap:run` — invoked from seeds.rb so
# it runs even if the Render dashboard's start command isn't kept in sync with
# render.yaml.
# ─────────────────────────────────────────────────────────────────────────────
if ENV["SKIP_BOOTSTRAP"].to_s.downcase != "true"
  puts ""
  puts "== Bootstrap (Shopify webhooks + backfill) =="
  begin
    Rails.application.load_tasks unless Rake::Task.task_defined?("bootstrap:run")
    Rake::Task["bootstrap:run"].invoke
  rescue => e
    warn "[seeds] bootstrap failed: #{e.class}: #{e.message} (continuing — set SKIP_BOOTSTRAP=true to silence)"
  end
end
