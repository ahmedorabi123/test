module RequestSpecHelpers
  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  def auth_headers(user)
    post "/api/v1/auth/login", params: { user: { email: user.email, password: user.password } }, as: :json
    token = json_response.dig(:data, :token)
    { "Authorization" => "Bearer #{token}" }
  end
end
