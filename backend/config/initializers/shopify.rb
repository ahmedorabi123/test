module Shopify
  SHOP_DOMAIN     = ENV.fetch("SHOPIFY_SHOP_DOMAIN", nil)
  ACCESS_TOKEN    = ENV.fetch("SHOPIFY_ADMIN_ACCESS_TOKEN", nil)
  API_SECRET      = ENV.fetch("SHOPIFY_API_SECRET", nil)
  API_VERSION     = ENV.fetch("SHOPIFY_API_VERSION", "2025-01")
  HMAC_BYPASS     = ENV.fetch("WEBHOOKS_HMAC_BYPASS", "false") == "true" && !Rails.env.production?
end
