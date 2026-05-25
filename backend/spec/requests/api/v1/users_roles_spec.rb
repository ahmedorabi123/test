require "rails_helper"

RSpec.describe "Users and roles API", type: :request do
  let(:admin) { create(:user, :admin) }

  it "lists users for admins" do
    create(:user, first_name: "Visible", last_name: "User")

    get "/api/v1/users", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data").map { |row| row.fetch("email") }).to include(admin.email)
  end

  it "lists roles for admins" do
    role = create(:role, name: "operations")

    get "/api/v1/roles", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data").map { |row| row.fetch("name") }).to include(role.name, "admin")
  end

  it "lists permissions through the dedicated policy file" do
    permission = create(:permission, resource: "roles", action: "read")

    get "/api/v1/permissions", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data").map { |row| row.fetch("key") }).to include("#{permission.resource}:#{permission.action}")
  end

  describe "POST /api/v1/roles" do
    it "creates a role with permissions for admins" do
      post "/api/v1/roles",
           params:  { role: { name: "warehouse_manager", description: "Manages warehouses", permissions: %w[warehouses:read warehouses:write] } },
           headers: auth_headers(admin),
           as:      :json

      expect(response).to have_http_status(:created)
      expect(json.dig("data", "name")).to eq("warehouse_manager")
      expect(json.dig("data", "permissions")).to match_array(%w[warehouses:read warehouses:write])
      expect(json.dig("data", "system")).to eq(false)
    end

    it "rejects unknown permission keys" do
      post "/api/v1/roles",
           params:  { role: { name: "x", permissions: %w[bogus:thing] } },
           headers: auth_headers(admin),
           as:      :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to include("bogus:thing")
    end

    it "denies non-admins" do
      operator = create(:user)
      post "/api/v1/roles",
           params:  { role: { name: "x", permissions: [] } },
           headers: auth_headers(operator),
           as:      :json
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "PATCH /api/v1/roles/:id" do
    it "updates a role and replaces its permissions" do
      role = create(:role, name: "ops_lead")
      role.permissions = [Permission.find_or_create_by!(resource: "orders", action: "read")]

      patch "/api/v1/roles/#{role.id}",
            params:  { role: { description: "lead the ops team", permissions: %w[orders:read orders:write] } },
            headers: auth_headers(admin),
            as:      :json

      expect(response).to have_http_status(:ok)
      expect(json.dig("data", "permissions")).to match_array(%w[orders:read orders:write])
      expect(json.dig("data", "description")).to eq("lead the ops team")
    end

    it "blocks renaming a system role" do
      admin_role = Role.find_or_create_by!(name: "admin")

      patch "/api/v1/roles/#{admin_role.id}",
            params:  { role: { name: "renamed" } },
            headers: auth_headers(admin),
            as:      :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to include("system role")
    end
  end

  describe "DELETE /api/v1/roles/:id" do
    it "deletes a non-system role with no users" do
      role = create(:role, name: "temporary")
      delete "/api/v1/roles/#{role.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(Role.find_by(id: role.id)).to be_nil
    end

    it "refuses to delete a system role" do
      admin_role = Role.find_or_create_by!(name: "admin")
      delete "/api/v1/roles/#{admin_role.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to include("system role")
    end

    it "refuses to delete a role assigned to users" do
      role = create(:role, name: "in_use")
      user = create(:user)
      user.roles << role

      delete "/api/v1/roles/#{role.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json["error"]).to include("assigned to users")
    end
  end

  describe "DELETE /api/v1/users/:id" do
    it "soft-deactivates regular users" do
      user = create(:user)

      delete "/api/v1/users/#{user.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(user.reload.active).to eq(false)
    end

    it "does not deactivate the current admin through delete" do
      delete "/api/v1/users/#{admin.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:forbidden)
      expect(admin.reload.active).to eq(true)
    end

    it "does not deactivate another admin" do
      other_admin = create(:user, :admin)

      delete "/api/v1/users/#{other_admin.id}", headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(other_admin.reload.active).to eq(true)
    end
  end

  def json
    JSON.parse(response.body)
  end
end
