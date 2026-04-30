module Shopify
  # Verifies Shopify webhook HMAC signatures.
  #
  # Shopify signs webhook payloads with the shared API secret using
  # HMAC-SHA256 + Base64. The header `X-Shopify-Hmac-Sha256` contains
  # the signature computed over the raw request body.
  #
  # In test/dev you can set WEBHOOKS_HMAC_BYPASS=true to skip verification.
  class HmacVerifier
    def self.verify(raw_body:, header_signature:, secret: ENV.fetch("SHOPIFY_API_SECRET", nil))
      return true if ENV["WEBHOOKS_HMAC_BYPASS"] == "true"
      return false if header_signature.blank? || secret.blank?

      computed = OpenSSL::HMAC.digest("sha256", secret, raw_body.to_s)
      expected = Base64.strict_encode64(computed)
      ActiveSupport::SecurityUtils.secure_compare(expected, header_signature)
    end
  end
end
