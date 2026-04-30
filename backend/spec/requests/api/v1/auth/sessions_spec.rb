require "rails_helper"

RSpec.describe "Api::V1::Auth::Sessions", type: :request do
  let!(:user) { create(:user, :admin, password: "password123!") }

  describe "POST /api/v1/auth/login" do
    it "returns 200 with a JWT token on valid credentials" do
      post "/api/v1/auth/login",
           params: { user: { email: user.email, password: "password123!" } },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response[:data][:token]).to be_present
      expect(json_response[:data][:user][:email]).to eq(user.email)
      expect(json_response[:data][:user][:roles]).to include("admin")
    end

    it "returns 401 with a password-specific message on invalid password" do
      post "/api/v1/auth/login",
           params: { user: { email: user.email, password: "wrong" } },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_response[:error][:type]).to eq("unauthorized")
      expect(json_response[:error][:detail]).to eq("Incorrect password")
    end

    it "returns 401 with an email-specific message for unknown email" do
      post "/api/v1/auth/login",
           params: { user: { email: "ghost@erp.local", password: "password123!" } },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(json_response[:error][:detail]).to eq("No account found with that email address")
    end

    it "returns 403 for deactivated accounts" do
      user.update!(active: false)
      post "/api/v1/auth/login",
           params: { user: { email: user.email, password: "password123!" } },
           as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/auth/me" do
    it "returns the current user when authenticated" do
      headers = auth_headers(user)
      get "/api/v1/auth/me", headers: headers

      expect(response).to have_http_status(:ok)
      expect(json_response[:data][:email]).to eq(user.email)
      expect(json_response[:data][:permissions]).to be_an(Array)
    end

    it "returns 401 without a token" do
      get "/api/v1/auth/me"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /api/v1/auth/logout" do
    it "revokes the token by rotating jti" do
      headers = auth_headers(user)
      original_jti = user.reload.jti

      delete "/api/v1/auth/logout", headers: headers
      expect(response).to have_http_status(:ok)

      expect(user.reload.jti).not_to eq(original_jti)

      # Old token must no longer be accepted
      get "/api/v1/auth/me", headers: headers
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
