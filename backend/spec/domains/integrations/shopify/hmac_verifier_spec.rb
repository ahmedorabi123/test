require "rails_helper"

RSpec.describe ::Shopify::HmacVerifier do
  let(:secret) { "shhh-secret" }
  let(:body)   { '{"id":123,"name":"#1001"}' }

  def sign(body, secret)
    Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body))
  end

  describe ".verify" do
    it "accepts a correctly signed body" do
      signature = sign(body, secret)
      expect(
        described_class.verify(raw_body: body, header_signature: signature, secret: secret)
      ).to be true
    end

    it "rejects a tampered body" do
      signature = sign(body, secret)
      expect(
        described_class.verify(raw_body: body + "x", header_signature: signature, secret: secret)
      ).to be false
    end

    it "rejects an empty signature" do
      expect(
        described_class.verify(raw_body: body, header_signature: "", secret: secret)
      ).to be false
    end

    it "rejects when secret is missing" do
      expect(
        described_class.verify(raw_body: body, header_signature: "abc", secret: nil)
      ).to be false
    end

    it "bypasses verification when WEBHOOKS_HMAC_BYPASS=true" do
      ClimateControl.modify("WEBHOOKS_HMAC_BYPASS" => "true") do
        expect(
          described_class.verify(raw_body: body, header_signature: "", secret: secret)
        ).to be true
      end
    rescue NameError
      # ClimateControl not available; fall back to direct ENV stubbing
      original = ENV["WEBHOOKS_HMAC_BYPASS"]
      ENV["WEBHOOKS_HMAC_BYPASS"] = "true"
      expect(
        described_class.verify(raw_body: body, header_signature: "", secret: secret)
      ).to be true
    ensure
      ENV["WEBHOOKS_HMAC_BYPASS"] = original if defined?(original)
    end
  end
end
