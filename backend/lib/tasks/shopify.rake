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

  desc "Diagnose Shopify webhook, sync cursor, and queue state"
  task diagnose: :environment do
    puts "Shopify diagnostics"
    puts "==================="
    puts "Rails env: #{Rails.env}"
    puts "READ_ONLY_SHOPIFY=#{ENV['READ_ONLY_SHOPIFY'].presence || '(unset)'}"
    puts "SHOPIFY_WRITES_ENABLED=#{ENV['SHOPIFY_WRITES_ENABLED'].presence || '(unset)'}"
    puts "SHOPIFY_PIPELINE_V2=#{ENV['SHOPIFY_PIPELINE_V2'].presence || '(unset)'}"
    puts

    puts "Supported topics (#{Shopify::EventNormalizer::SUPPORTED_TOPICS.size})"
    Shopify::EventNormalizer::SUPPORTED_TOPICS.keys.sort.each { |topic| puts "- #{topic}" }
    puts

    puts "Registered webhooks"
    begin
      registered = Shopify::Client.new.get("webhooks.json").fetch("webhooks", [])
      if registered.empty?
        puts "- none"
      else
        registered.sort_by { |webhook| webhook["topic"].to_s }.each do |webhook|
          puts "- #{webhook['topic']} -> #{webhook['address']}"
        end
      end
    rescue => e
      puts "- unavailable: #{e.class}: #{e.message}"
    end
    puts

    puts "Recent webhook events"
    WebhookEvent.order(created_at: :desc).limit(10).each do |event|
      state = event.processed_at.present? ? "processed" : (event.error.present? ? "failed" : "pending")
      puts "- #{event.created_at.iso8601} #{event.topic} #{event.external_id} #{state} #{event.error}"
    end
    puts "- none" if WebhookEvent.none?
    puts

    puts "Sync cursors"
    {
      "products/orders/customers" => Rails.root.join("tmp/shopify_last_sync_at.txt"),
      "inventory" => Rails.root.join("tmp/shopify_inventory_last_sync_at.txt")
    }.each do |label, path|
      puts "- #{label}: #{File.exist?(path) ? File.read(path).strip.presence || '(blank)' : '(missing)'}"
    end
    puts

    puts "Queue adapter: #{ActiveJob::Base.queue_adapter_name}"
    if defined?(Sidekiq::Queue)
      Sidekiq::Queue.all.sort_by(&:name).each do |queue|
        puts "- #{queue.name}: #{queue.size} job(s)"
      end
    else
      puts "- Sidekiq queue stats unavailable in this process"
    end
  end
end
