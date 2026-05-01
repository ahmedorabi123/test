# Seeds are intentionally minimal — only the data needed to log in and use accounting.
# Everything else (products, orders, customers, inventory, warehouses, fulfillments,
# refunds, suppliers) comes from Shopify via the bootstrap task, or is created through
# the UI.
#
# Safe to run multiple times (idempotent).

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
# 2. Users
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
puts "   │  LOGIN CREDENTIALS (all passwords: changeme123!)      │"
puts "   │  #{admin_email.ljust(22)} → Admin (full access)          │"
puts "   │  ops@erp.local         → Operations                   │"
puts "   │  viewer@erp.local      → Viewer (read-only)           │"
puts "   │  accountant@erp.local  → Accountant                   │"
puts "   └───────────────────────────────────────────────────────┘"

# ─────────────────────────────────────────────────────────────────────────────
# 3. Chart of Accounts (required for accounting journal entries to post)
# ─────────────────────────────────────────────────────────────────────────────
puts "== Seeding Chart of Accounts =="

coa = [
  # ── Assets ──────────────────────────────────────────────────────────────────
  { code: "1000", name: "Cash & Cash Equivalents",  type: "asset",     side: "debit",  desc: "Cash on hand and bank balances" },
  { code: "1100", name: "Accounts Receivable",      type: "asset",     side: "debit",  desc: "Amounts owed by customers" },
  { code: "1200", name: "Inventory",                type: "asset",     side: "debit",  desc: "Goods held for sale" },
  { code: "1300", name: "Prepaid Expenses",         type: "asset",     side: "debit",  desc: "Prepaid costs" },
  { code: "1500", name: "Property & Equipment",     type: "asset",     side: "debit",  desc: "Tangible fixed assets" },
  # ── Liabilities ─────────────────────────────────────────────────────────────
  { code: "2000", name: "Accounts Payable",         type: "liability", side: "credit", desc: "Amounts owed to suppliers" },
  { code: "2100", name: "Accrued Liabilities",      type: "liability", side: "credit", desc: "Accrued expenses" },
  { code: "2200", name: "Sales Tax Payable",        type: "liability", side: "credit", desc: "VAT / sales tax collected" },
  { code: "2300", name: "Customer Deposits",        type: "liability", side: "credit", desc: "Advance payments from customers" },
  # ── Equity ──────────────────────────────────────────────────────────────────
  { code: "3000", name: "Owner's Equity",           type: "equity",    side: "credit", desc: "Paid-in capital" },
  { code: "3100", name: "Retained Earnings",        type: "equity",    side: "credit", desc: "Cumulative net income" },
  # ── Revenue ─────────────────────────────────────────────────────────────────
  { code: "4000", name: "Sales Revenue",            type: "revenue",   side: "credit", desc: "Product sales income" },
  { code: "4100", name: "Shipping Revenue",         type: "revenue",   side: "credit", desc: "Shipping fees charged to customers" },
  { code: "4200", name: "Other Revenue",            type: "revenue",   side: "credit", desc: "Miscellaneous income" },
  # ── Expenses ────────────────────────────────────────────────────────────────
  { code: "5000", name: "Cost of Goods Sold",       type: "expense",   side: "debit",  desc: "Direct cost of products sold" },
  { code: "5100", name: "Shipping & Fulfillment",   type: "expense",   side: "debit",  desc: "Outbound shipping costs" },
  { code: "5200", name: "Returns & Allowances",     type: "expense",   side: "debit",  desc: "Customer returns" },
  { code: "6000", name: "Payroll Expense",          type: "expense",   side: "debit",  desc: "Salaries and wages" },
  { code: "6100", name: "Rent & Occupancy",         type: "expense",   side: "debit",  desc: "Showroom and office rent" },
  { code: "6200", name: "Marketing & Advertising",  type: "expense",   side: "debit",  desc: "Ad spend and promotions" },
  { code: "6300", name: "Technology & Software",    type: "expense",   side: "debit",  desc: "SaaS, hosting, dev tools" },
  { code: "6900", name: "General & Administrative", type: "expense",   side: "debit",  desc: "Other G&A expenses" },
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

puts ""
puts "========================================================"
puts "  Seed complete."
puts "  Products, orders, customers, inventory, warehouses,"
puts "  fulfillments, and refunds are pulled from Shopify"
puts "  automatically on server start (bootstrap task)."
puts "========================================================"
