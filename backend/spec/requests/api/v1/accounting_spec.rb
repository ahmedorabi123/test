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
end
