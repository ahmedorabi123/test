namespace :shopify do
  desc "Register all required Shopify webhooks against WEBHOOK_BASE_URL"
  task register_webhooks: :environment do
    base = ENV.fetch("WEBHOOK_BASE_URL") do
      abort "WEBHOOK_BASE_URL not set (e.g. https://xxx.trycloudflare.com)"
    end

    client = Shopify::Client.new
    topics = Shopify::EventNormalizer::SUPPORTED_TOPICS.keys

    existing = client.get("webhooks.json").fetch("webhooks", []).index_by { |w| w["topic"] }

    topics.each do |topic|
      callback = "#{base}/webhooks/shopify/#{topic}"
      if (current = existing[topic])
        if current["address"] == callback
          puts "=  #{topic}  (already registered)"
          next
        else
          client.delete("webhooks/#{current["id"]}.json")
          puts "-  #{topic}  (deleted stale registration)"
        end
      end

      client.post("webhooks.json", payload: {
        webhook: {
          topic:   topic,
          address: callback,
          format:  "json"
        }
      })
      puts "+  #{topic}  -> #{callback}"
    rescue => e
      warn "!  #{topic}  FAILED: #{e.class}: #{e.message}"
    end
  end

  desc "List currently registered Shopify webhooks"
  task list_webhooks: :environment do
    client = Shopify::Client.new
    webhooks = client.get("webhooks.json").fetch("webhooks", [])
    if webhooks.empty?
      puts "(none registered)"
    else
      webhooks.each do |w|
        puts "#{w["topic"].ljust(30)} -> #{w["address"]}"
      end
    end
  end
end
