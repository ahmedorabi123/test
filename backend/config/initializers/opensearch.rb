OPENSEARCH_CLIENT = OpenSearch::Client.new(
  url: ENV.fetch("OPENSEARCH_URL", "http://localhost:9200"),
  retry_on_failure: 3,
  transport_options: { request: { timeout: 10 } },
  log: Rails.env.development?
)
