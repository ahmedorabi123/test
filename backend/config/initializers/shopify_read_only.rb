if Rails.env.production? && ENV["READ_ONLY_SHOPIFY"].to_s.downcase != "true" && ENV["SHOPIFY_WRITES_ENABLED"].to_s.downcase != "true"
  raise "[shopify] Set READ_ONLY_SHOPIFY=true in production, or explicitly set SHOPIFY_WRITES_ENABLED=true to allow Admin API writes."
end