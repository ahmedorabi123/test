Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Comma-separated list of allowed frontend origins, plus tunnel regexes for dev.
    local_dev_origins = %w[
      http://localhost:5173
      http://localhost:5174
      http://127.0.0.1:5173
      http://127.0.0.1:5174
    ]
    configured_origins = ENV.fetch("FRONTEND_URL", "").split(",").map(&:strip).reject(&:blank?)
    allowed = (local_dev_origins + configured_origins).uniq
    # Optional production origin (e.g. Vercel deployment URL).
    allowed << ENV["FRONTEND_ORIGIN"] if ENV["FRONTEND_ORIGIN"].present?
    origins(
      *allowed,
      /\Ahttps:\/\/.*\.vercel\.app\z/,
      /\Ahttps:\/\/.*\.onrender\.com\z/,
      /\Ahttps:\/\/.*\.ngrok-free\.(dev|app)\z/,
      /\Ahttps:\/\/.*\.ngrok\.(io|app)\z/,
      /\Ahttps:\/\/.*\.trycloudflare\.com\z/,
      /\Ahttps:\/\/.*\.loca\.lt\z/
    )
    resource "*",
      headers: :any,
      methods: [ :get, :post, :put, :patch, :delete, :options, :head ],
      expose: [ "Authorization" ]
  end
end
