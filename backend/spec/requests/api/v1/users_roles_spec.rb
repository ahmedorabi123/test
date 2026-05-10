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

  def json
    JSON.parse(response.body)
  end
end
