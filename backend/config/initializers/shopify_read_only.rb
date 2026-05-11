if Rails.env.production? && ENV["READ_ONLY_SHOPIFY"].to_s.downcase != "true" && ENV["SHOPIFY_WRITES_ENABLED"].to_s.downcase != "true"
  Rails.logger.warn("[shopify] READ_ONLY_SHOPIFY is unset; Shopify::Client defaults to read-only. Set READ_ONLY_SHOPIFY=true explicitly in production.")
end