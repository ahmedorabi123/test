require "rails_helper"

RSpec.describe "Api::V1::Accounting", type: :request do
  let(:admin)      { create(:user, :admin) }
  let(:viewer) do
    user = create(:user)
    # Give read permission via viewer role
    role = Role.find_or_create_by!(name: "viewer_test_#{SecureRandom.hex(4)}")
    perm = Permission.find_or_create_by!(resource: "accounting", action: "read")
    role.permissions << perm
    user.roles << role
    user
  end

  # Seed minimal COA needed for tests
  let!(:ar_account)       { create(:account, code: "1100", name: "Accounts Receivable",  account_type: "asset",     normal_side: "debit") }
  let!(:revenue_account)  { create(:account, code: "4000", name: "Sales Revenue",         account_type: "revenue",   normal_side: "credit") }
  let!(:tax_account)      { create(:account, code: "2200", name: "Sales Tax Payable",     account_type: "liability", normal_side: "credit") }
  let!(:shipping_account) { create(:account, code: "4100", name: "Shipping Revenue",      account_type: "revenue",   normal_side: "credit") }

  # ─── GET /api/v1/accounting/accounts ──────────────────────────────────────
  describe "GET /api/v1/accounting/accounts" do
    it "returns 401 without auth" do
      get "/api/v1/accounting/accounts"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns all active accounts for admin" do
      get "/api/v1/accounting/accounts", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json_response[:data].size).to eq(4)
      expect(json_response[:data].first).to include(:code, :name, :account_type, :normal_side)
    end

    it "returns accounts ordered by code" do
      get "/api/v1/accounting/accounts", headers: auth_headers(admin)
      codes = json_response[:data].map { |a| a[:code] }
      expect(codes).to eq(codes.sort)
    end
  end

  # ─── GET /api/v1/accounting/journal_entries ──────────────────────────────
  describe "GET /api/v1/accounting/journal_entries" do
    let!(:paid_order) do
      create(:order, financial_status: "paid",
        subtotal_price: 100, total_discount: 0, total_tax: 8, total_shipping: 5, total_price: 113)
    end
    let!(:entry) { Accounting::PostSaleJournalHandler.call(paid_order) }

    it "returns paginated journal entries" do
      get "/api/v1/accounting/journal_entries", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body[:data]).to be_an(Array)
      expect(body[:meta]).to include(:page, :per_page, :total)
    end

    it "filters by entry_type" do
      get "/api/v1/accounting/journal_entries",
          params: { entry_type: "sale" },
          headers: auth_headers(admin)
      expect(json_response[:data].size).to eq(1)
      expect(json_response[:data].first[:entry_type]).to eq("sale")
    end

    it "filters by date range" do
      get "/api/v1/accounting/journal_entries",
          params: { from: Date.tomorrow.to_s },
          headers: auth_headers(admin)
      expect(json_response[:data]).to be_empty
    end
  end

  # ─── GET /api/v1/accounting/journal_entries/:id ───────────────────────────
  describe "GET /api/v1/accounting/journal_entries/:id" do
    let!(:paid_order) do
      create(:order, financial_status: "paid",
        subtotal_price: 100, total_discount: 0, total_tax: 8, total_shipping: 5, total_price: 113)
    end
    let!(:entry) { Accounting::PostSaleJournalHandler.call(paid_order) }

    it "returns entry with lines" do
      get "/api/v1/accounting/journal_entries/#{entry.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = json_response[:data]
      expect(body[:lines]).to be_an(Array)
      expect(body[:lines].size).to be >= 2
    end

    it "returns 404 for unknown id" do
      get "/api/v1/accounting/journal_entries/00000000-0000-0000-0000-000000000000",
          headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ─── GET /api/v1/accounting/trial_balance ─────────────────────────────────
  describe "GET /api/v1/accounting/trial_balance" do
    let!(:paid_order) do
      create(:order, financial_status: "paid",
        subtotal_price: 100, total_discount: 0, total_tax: 8, total_shipping: 5, total_price: 113)
    end
    before { Accounting::PostSaleJournalHandler.call(paid_order) }

    it "returns balanced trial balance" do
      get "/api/v1/accounting/trial_balance", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body[:balanced]).to eq(true)
      expect(body[:data]).to be_an(Array)
      expect(body[:totals][:debits]).to eq(body[:totals][:credits])
    end

    it "accepts as_of date param" do
      get "/api/v1/accounting/trial_balance",
          params: { as_of: 1.year.ago.to_date.to_s },
          headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json_response[:data]).to be_empty
    end
  end

  # ─── GET /api/v1/accounting/pnl ───────────────────────────────────────────
  describe "GET /api/v1/accounting/pnl" do
    let!(:paid_order) do
      create(:order, financial_status: "paid", placed_at: Date.current,
        subtotal_price: 100, total_discount: 0, total_tax: 8, total_shipping: 5, total_price: 113)
    end
    before { Accounting::PostSaleJournalHandler.call(paid_order) }

    it "returns P&L for current month" do
      get "/api/v1/accounting/pnl", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body[:revenue]).to be_an(Array)
      expect(body[:expenses]).to be_an(Array)
      expect(body[:net_income]).to eq(body[:total_revenue] - body[:total_expenses])
    end

    it "returns empty P&L for a future period" do
      get "/api/v1/accounting/pnl",
          params: { from: 1.year.from_now.to_date.to_s, to: 2.years.from_now.to_date.to_s },
          headers: auth_headers(admin)
      expect(json_response[:total_revenue]).to eq(0.0)
    end
  end

  # ─── POST /api/v1/accounting/post_order/:order_id ─────────────────────────
  describe "POST /api/v1/accounting/post_order/:order_id" do
    let!(:paid_order) do
      create(:order, financial_status: "paid",
        subtotal_price: 100, total_discount: 0, total_tax: 8, total_shipping: 5, total_price: 113)
    end

    it "posts a journal entry and returns 201" do
      post "/api/v1/accounting/post_order/#{paid_order.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
      expect(json_response[:data][:status]).to eq("posted")
    end

    it "returns 200 (already posted) on second call" do
      Accounting::PostSaleJournalHandler.call(paid_order)
      post "/api/v1/accounting/post_order/#{paid_order.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for unknown order" do
      post "/api/v1/accounting/post_order/00000000-0000-0000-0000-000000000000",
           headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end

    it "requires auth" do
      post "/api/v1/accounting/post_order/#{paid_order.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ─── Viewer is also allowed to read (accounting:read) ─────────────────────
  describe "authorization" do
    it "viewer can read accounts" do
      get "/api/v1/accounting/accounts", headers: auth_headers(viewer)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "accounts search (q)" do
    before do
      create(:account, code: "1200", name: "Inventory",         account_type: "asset",     normal_side: "debit")
      create(:account, code: "6000", name: "Salaries Expense",  account_type: "expense",   normal_side: "debit")
      create(:account, code: "2000", name: "Accounts Payable",  account_type: "liability", normal_side: "credit")
    end

    it "matches by code prefix" do
      get "/api/v1/accounting/accounts", params: { q: "12" }, headers: auth_headers(admin)
      codes = json_response[:data].map { |a| a[:code] }
      expect(codes).to include("1200")
      expect(codes).not_to include("6000")
    end

    it "matches by name substring (case-insensitive)" do
      get "/api/v1/accounting/accounts", params: { q: "PAYABLE" }, headers: auth_headers(admin)
      codes = json_response[:data].map { |a| a[:code] }
      expect(codes).to include("2000")
      expect(codes).not_to include("1200", "6000")
    end
  end

  describe "POST /journal_entries with supplier_id" do
    it "links material-supplier lines to the supplier" do
      create(:account, code: "1500", name: "Materials",        account_type: "asset",     normal_side: "debit")
      create(:account, code: "2100", name: "Materials Payable", account_type: "liability", normal_side: "credit")
      supplier = create(:supplier, kind: "material")

      post "/api/v1/accounting/journal_entries",
        params: {
          entry_date: Date.current.iso8601,
          description: "Fabric purchase",
          currency: "EGP",
          lines: [
            { account_code: "1500", side: "debit",  amount: "100.00", supplier_id: supplier.id, description: "Cotton 10m" },
            { account_code: "2100", side: "credit", amount: "100.00", supplier_id: supplier.id, description: "AP - fabric" }
          ]
        }.to_json,
        headers: auth_headers(admin).merge("Content-Type" => "application/json")

      expect(response).to have_http_status(:created)
      lines = json_response[:data][:lines]
      expect(lines.map { |l| l[:supplier_id] }.uniq).to eq([ supplier.id ])
      expect(lines.first[:supplier_name]).to eq(supplier.name)
    end
  end

  describe "payroll_entries route is removed" do
    it "returns 404" do
      post "/api/v1/accounting/payroll_entries",
        params: { period: "2025-04", total_amount: "100" }.to_json,
        headers: auth_headers(admin).merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:not_found)
    end
  end

  # ─── Search + Account Ledger ──────────────────────────────────────────────
  describe "GET /api/v1/accounting/journal_entries with search params" do
    let!(:entry_a) do
      JournalEntry.post!(
        { entry_date: Date.current, description: "Office supplies invoice", entry_type: "manual" },
        [
          { account_code: "1100", side: "debit",  amount: 50, description: "stationery" },
          { account_code: "4000", side: "credit", amount: 50, description: "stationery" }
        ]
      )
    end
    let!(:entry_b) do
      JournalEntry.post!(
        { entry_date: Date.current, description: "Coffee for staff", entry_type: "manual" },
        [
          { account_code: "1100", side: "debit",  amount: 5_000, description: "coffee beans" },
          { account_code: "4000", side: "credit", amount: 5_000, description: "coffee beans" }
        ]
      )
    end

    it "filters by q (substring)" do
      get "/api/v1/accounting/journal_entries", params: { q: "coffee" }, headers: auth_headers(admin)
      ids = json_response[:data].map { |e| e[:id] }
      expect(ids).to include(entry_b.id)
      expect(ids).not_to include(entry_a.id)
    end

    it "filters by min_amount/max_amount" do
      get "/api/v1/accounting/journal_entries",
          params: { min_amount: "1000" },
          headers: auth_headers(admin)
      ids = json_response[:data].map { |e| e[:id] }
      expect(ids).to include(entry_b.id)
      expect(ids).not_to include(entry_a.id)
    end

    it "filters by account_code prefix" do
      get "/api/v1/accounting/journal_entries",
          params: { account_code: "11" },
          headers: auth_headers(admin)
      ids = json_response[:data].map { |e| e[:id] }
      expect(ids).to include(entry_a.id, entry_b.id)
    end
  end

  describe "GET /api/v1/accounting/accounts/:code/ledger" do
    before do
      JournalEntry.post!(
        { entry_date: Date.current - 2, description: "Open" },
        [
          { account_code: "1100", side: "debit",  amount: 100 },
          { account_code: "4000", side: "credit", amount: 100 }
        ]
      )
      JournalEntry.post!(
        { entry_date: Date.current, description: "More" },
        [
          { account_code: "1100", side: "debit",  amount: 50 },
          { account_code: "4000", side: "credit", amount: 50 }
        ]
      )
    end

    it "returns running balance for the account (debit-normal)" do
      get "/api/v1/accounting/accounts/1100/ledger", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      rows = json_response[:data]
      expect(rows.size).to eq(2)
      expect(rows.first[:running_balance]).to eq(100.0)
      expect(rows.last[:running_balance]).to eq(150.0)
      expect(json_response[:meta][:account][:code]).to eq("1100")
    end

    it "404s for unknown code" do
      get "/api/v1/accounting/accounts/9999/ledger", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end
end
