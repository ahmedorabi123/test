class Rack::Attack
  # Cache store
  Rack::Attack.cache.store = ActiveSupport::Cache::RedisCacheStore.new(
    url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
  )

  # Throttle API requests by IP
  throttle("api/ip", limit: 300, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/api/")
  end

  # Throttle login attempts
  throttle("login/ip", limit: 10, period: 1.minute) do |req|
    req.ip if req.path == "/api/v1/auth/login" && req.post?
  end

  # Login throttle by email (per-account brute force protection)
  throttle("login/email", limit: 5, period: 20.seconds) do |req|
    if req.path == "/api/v1/auth/login" && req.post?
      begin
        body = JSON.parse(req.body.read || "{}")
        req.body.rewind
        body.dig("user", "email")&.to_s&.downcase&.presence
      rescue JSON::ParserError
        nil
      end
    end
  end

  # Webhook throttle: Shopify can burst on replays
  throttle("webhooks/ip", limit: 600, period: 1.minute) do |req|
    req.ip if req.path.start_with?("/webhooks/")
  end

  # Custom 429 response (JSON)
  self.throttled_responder = lambda do |request|
    retry_after = (request.env["rack.attack.match_data"] || {})[:period] || 60
    [
      429,
      { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
      [{ error: { status: 429, type: "too_many_requests", detail: "Rate limit exceeded" } }.to_json]
    ]
  end

  # Safelist local development
  safelist("localhost") { |req| req.ip == "127.0.0.1" || req.ip == "::1" } if Rails.env.development?
end
