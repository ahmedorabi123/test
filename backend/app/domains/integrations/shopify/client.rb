module Shopify
  # Thin GraphQL Admin API client.
  # Handles auth header, base URL, retries, and response parsing.
  #
  # Usage:
  #   client = Integrations::Shopify::Client.new
  #   client.query("{ shop { name } }")
  #
  class Client
    class ApiError < StandardError; end
    class RateLimitError < ApiError; end
    class AuthError < ApiError; end
    class ReadOnlyError < ApiError; end

    DEFAULT_TIMEOUT = 15

    def initialize(
      shop_domain:     ENV.fetch("SHOPIFY_SHOP_DOMAIN"),
      access_token:    ENV.fetch("SHOPIFY_ADMIN_ACCESS_TOKEN"),
      api_version:     ENV.fetch("SHOPIFY_API_VERSION", "2025-01"),
      timeout:         DEFAULT_TIMEOUT
    )
      @shop_domain  = shop_domain
      @access_token = access_token
      @api_version  = api_version
      @timeout      = timeout
    end

    # REST GET for webhook registration etc.
    def get(path, params: {})
      response = connection.get(rest_path(path), params)
      handle_rest(response)
    end

    def post(path, payload: {})
      enforce_read_only!(path)
      response = connection.post(rest_path(path), payload.to_json)
      handle_rest(response)
    end

    def put(path, payload: {})
      enforce_read_only!(path)
      response = connection.put(rest_path(path), payload.to_json)
      handle_rest(response)
    end

    def delete(path)
      enforce_read_only!(path)
      response = connection.delete(rest_path(path))
      handle_rest(response)
    end

    # GraphQL queries are also potentially write operations (mutations).
    # When read-only, refuse any GraphQL operation that contains 'mutation '.
    def query(query_string, variables: {})
      if read_only? && query_string.to_s =~ /\bmutation\b/i
        raise ReadOnlyError, "Shopify is in read-only mode (READ_ONLY_SHOPIFY=true); GraphQL mutations are blocked."
      end
      body = { query: query_string, variables: variables }.compact
      response = connection.post(graphql_path, body.to_json)
      parse_response(response)
    end

    # Cursor-based pagination for REST list endpoints (Shopify 2021-04+).
    # Yields or returns a flat array of all records across all pages.
    # Example: client.paginated("products.json", key: "products", params: { status: "active" })
    def paginated(path, key:, params: {})
      return enum_for(:paginated_each, path, key: key, params: params).to_a unless block_given?

      paginated_each(path, key: key, params: params) { |record| yield record }
    end

    # Streams each record one-at-a-time across all pages without holding the
    # whole result set in memory. Use this for large backfills (orders,
    # customers) on memory-constrained dynos.
    def paginated_each(path, key:, params: {})
      return enum_for(:paginated_each, path, key: key, params: params) unless block_given?

      request_params = params.merge(limit: 250)
      next_page_info = nil

      loop do
        current_params = next_page_info ? { limit: 250, page_info: next_page_info } : request_params
        response = connection.get(rest_path(path), current_params)
        raise AuthError,     "Invalid Shopify credentials"         if response.status == 401
        raise RateLimitError, "Shopify rate limit hit"              if response.status == 429
        raise ApiError,      "HTTP #{response.status}: #{response.body}" unless response.success?

        body  = JSON.parse(response.body)
        batch = body[key] || []
        batch.each { |record| yield record }
        batch = nil # rubocop:disable Lint/UselessAssignment - encourage GC

        link_header = response.headers["link"]
        match       = link_header&.match(/<([^>]+)>;\s*rel="next"/)
        break unless match

        next_uri       = URI.parse(match[1])
        next_page_info = CGI.parse(next_uri.query.to_s)["page_info"]&.first
        break unless next_page_info
      end
    end

    private

    attr_reader :shop_domain, :access_token, :api_version, :timeout

    def read_only?
      return true if ENV["READ_ONLY_SHOPIFY"].to_s.downcase == "true"

      ENV["SHOPIFY_WRITES_ENABLED"].to_s.downcase != "true"
    end

    def enforce_read_only!(path)
      return unless read_only?
      # Webhook (re-)registration is integration plumbing, not a data write.
      # Allow it to proceed even in READ_ONLY_SHOPIFY mode so deploys / URL
      # changes can self-heal without flipping a global write flag.
      return if path.to_s.start_with?("webhooks")
      raise ReadOnlyError, "Shopify is in read-only mode (READ_ONLY_SHOPIFY=true); writes to #{path} are blocked."
    end

    def connection
      @connection ||= Faraday.new(url: "https://#{shop_domain}") do |f|
        f.request :retry, max: 2, interval: 0.5,
                  exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]
        f.options.timeout = timeout
        f.headers["X-Shopify-Access-Token"] = access_token
        f.headers["Content-Type"] = "application/json"
        f.headers["Accept"] = "application/json"
        f.adapter Faraday.default_adapter
      end
    end

    def graphql_path
      "/admin/api/#{api_version}/graphql.json"
    end

    def rest_path(path)
      "/admin/api/#{api_version}/#{path.sub(%r{\A/}, "")}"
    end

    def parse_response(response)
      raise AuthError, "Invalid Shopify credentials"        if response.status == 401
      raise RateLimitError, "Shopify rate limit hit"         if response.status == 429
      raise ApiError, "HTTP #{response.status}: #{response.body}" unless response.success?

      body = JSON.parse(response.body)
      if body["errors"].present?
        raise ApiError, "GraphQL errors: #{body["errors"].inspect}"
      end
      body["data"]
    end

    def handle_rest(response)
      raise AuthError, "Invalid Shopify credentials"        if response.status == 401
      raise RateLimitError, "Shopify rate limit hit"         if response.status == 429
      raise ApiError, "HTTP #{response.status}: #{response.body}" unless response.success?

      response.body.present? ? JSON.parse(response.body) : {}
    end
  end
end
