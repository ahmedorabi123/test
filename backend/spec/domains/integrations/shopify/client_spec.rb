require "rails_helper"

RSpec.describe ::Shopify::Client do
  let(:shop_domain)  { "test-shop.myshopify.com" }
  let(:access_token) { "shpat_fake" }
  let(:api_version)  { "2025-01" }
  let(:client) do
    described_class.new(
      shop_domain:  shop_domain,
      access_token: access_token,
      api_version:  api_version
    )
  end

  describe "#query (GraphQL)" do
    it "POSTs to the GraphQL endpoint with auth header and returns data" do
      stub = stub_request(:post, "https://#{shop_domain}/admin/api/#{api_version}/graphql.json")
        .with(
          headers: { "X-Shopify-Access-Token" => access_token, "Content-Type" => "application/json" },
          body: hash_including("query" => "{ shop { name } }")
        )
        .to_return(status: 200, body: { data: { shop: { name: "ACME" } } }.to_json)

      result = client.query("{ shop { name } }")
      expect(stub).to have_been_requested
      expect(result).to eq("shop" => { "name" => "ACME" })
    end

    it "raises AuthError on 401" do
      stub_request(:post, /graphql/).to_return(status: 401, body: "unauthorized")
      expect { client.query("{ shop { name } }") }.to raise_error(described_class::AuthError)
    end

    it "raises RateLimitError on 429" do
      stub_request(:post, /graphql/).to_return(status: 429, body: "slow down")
      expect { client.query("{ shop { name } }") }.to raise_error(described_class::RateLimitError)
    end

    it "raises ApiError when GraphQL returns errors array" do
      stub_request(:post, /graphql/).to_return(
        status: 200,
        body:   { errors: [{ message: "Field 'foo' doesn't exist" }] }.to_json
      )
      expect { client.query("{ foo }") }.to raise_error(described_class::ApiError, /Field 'foo'/)
    end
  end

  describe "#get (REST)" do
    it "GETs the REST endpoint and parses JSON" do
      stub = stub_request(:get, "https://#{shop_domain}/admin/api/#{api_version}/webhooks.json")
        .to_return(status: 200, body: { webhooks: [] }.to_json)

      result = client.get("webhooks.json")
      expect(stub).to have_been_requested
      expect(result).to eq("webhooks" => [])
    end
  end

  describe "READ_ONLY_SHOPIFY guard" do
    around do |example|
      original = ENV["READ_ONLY_SHOPIFY"]
      ENV["READ_ONLY_SHOPIFY"] = "true"
      example.run
    ensure
      ENV["READ_ONLY_SHOPIFY"] = original
    end

    it "blocks REST POST to non-webhook paths" do
      expect { client.post("products.json", payload: { product: { title: "x" } }) }
        .to raise_error(described_class::ReadOnlyError, /read-only/)
    end

    it "blocks REST PUT" do
      expect { client.put("products/123.json", payload: { product: { title: "x" } }) }
        .to raise_error(described_class::ReadOnlyError)
    end

    it "blocks REST DELETE to non-webhook paths" do
      expect { client.delete("products/123.json") }
        .to raise_error(described_class::ReadOnlyError)
    end

    it "blocks GraphQL mutations" do
      expect { client.query("mutation { productCreate(input: {}) { product { id } } }") }
        .to raise_error(described_class::ReadOnlyError, /mutations/)
    end

    it "still allows GraphQL queries" do
      stub_request(:post, /graphql/).to_return(status: 200, body: { data: { shop: { name: "ACME" } } }.to_json)
      expect { client.query("{ shop { name } }") }.not_to raise_error
    end

    it "blocks webhook registration" do
      expect { client.post("webhooks.json", payload: { webhook: {} }) }
        .to raise_error(described_class::ReadOnlyError)
    end

    it "blocks webhook deletion" do
      expect { client.delete("webhooks/1.json") }
        .to raise_error(described_class::ReadOnlyError)
    end

    it "allows REST GETs (reads always permitted)" do
      stub_request(:get, /products\.json/).to_return(status: 200, body: { products: [] }.to_json)
      expect { client.get("products.json") }.not_to raise_error
    end
  end

  it "defaults to read-only unless SHOPIFY_WRITES_ENABLED is explicit" do
    original_read_only = ENV["READ_ONLY_SHOPIFY"]
    original_writes = ENV["SHOPIFY_WRITES_ENABLED"]
    ENV.delete("READ_ONLY_SHOPIFY")
    ENV.delete("SHOPIFY_WRITES_ENABLED")

    expect { client.post("products.json", payload: { product: { title: "x" } }) }
      .to raise_error(described_class::ReadOnlyError)
  ensure
    ENV["READ_ONLY_SHOPIFY"] = original_read_only
    ENV["SHOPIFY_WRITES_ENABLED"] = original_writes
  end
end
