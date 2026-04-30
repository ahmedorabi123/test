namespace :erp do
  desc "Diagnose the ERP environment — DB, users, roles, permissions, services"
  task doctor: :environment do
    ok   = ->(msg) { puts "  \e[32m✓\e[0m #{msg}" }
    warn = ->(msg) { puts "  \e[33m⚠\e[0m #{msg}" }
    fail_check = ->(msg) { puts "  \e[31m✗\e[0m #{msg}" }

    puts "\n\e[1mERP Doctor\e[0m  (env=#{Rails.env})"
    puts "──────────────────────────────────────────────"
    exit_code = 0

    # 1. Database
    begin
      ActiveRecord::Base.connection.execute("SELECT 1")
      db = ActiveRecord::Base.connection_db_config.database
      ok.call("Database reachable (#{db})")
    rescue StandardError => e
      fail_check.call("Database UNREACHABLE: #{e.class}: #{e.message}")
      exit_code = 1
    end

    # 2. Users
    begin
      count = User.count
      if count >= 4
        ok.call("Users seeded (#{count} total)")
      elsif count > 0
        warn.call("Only #{count} users — expected 4 from seeds. Run: bin/rails db:seed")
      else
        fail_check.call("No users found. Run: bin/rails db:seed")
        exit_code = 1
      end

      admin_email = ENV.fetch("ADMIN_EMAIL", "admin@erp.local")
      admin       = User.find_by(email: admin_email)
      if admin && admin.valid_password?(ENV.fetch("ADMIN_PASSWORD", "changeme123!"))
        ok.call("Admin password matches ADMIN_PASSWORD env (#{admin_email})")
      elsif admin
        warn.call("Admin exists but password does NOT match ADMIN_PASSWORD env. Re-run db:seed to sync.")
      else
        fail_check.call("Admin user #{admin_email} missing.")
        exit_code = 1
      end
    rescue StandardError => e
      fail_check.call("User check failed: #{e.message}")
      exit_code = 1
    end

    # 3. Roles
    role_count = Role.count rescue 0
    if role_count >= 4
      ok.call("Roles seeded (#{role_count})")
    else
      fail_check.call("Missing roles — got #{role_count}, expected ≥ 4")
      exit_code = 1
    end

    # 4. Permissions
    perm_count = Permission.count rescue 0
    if perm_count >= 30
      ok.call("Permissions seeded (#{perm_count})")
    else
      warn.call("Only #{perm_count} permissions — expected ≥ 30")
    end

    # 5. Redis
    begin
      redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")
      Redis.new(url: redis_url).ping
      ok.call("Redis reachable (#{redis_url})")
    rescue StandardError => e
      warn.call("Redis unreachable: #{e.message}")
    end

    # 6. Sidekiq (uses Redis)
    begin
      require "sidekiq/api"
      stats = Sidekiq::Stats.new
      ok.call("Sidekiq reachable (processed=#{stats.processed}, queues=#{stats.queues.size})")
    rescue StandardError => e
      warn.call("Sidekiq stats unavailable: #{e.message}")
    end

    # 7. OpenSearch (optional)
    if defined?(Opensearch::CLIENT) && Opensearch::CLIENT
      begin
        Opensearch::CLIENT.info
        ok.call("OpenSearch reachable")
      rescue StandardError => e
        warn.call("OpenSearch unreachable: #{e.message}")
      end
    end

    # 8. Shopify env
    shop_domain = ENV["SHOPIFY_SHOP_DOMAIN"]
    token       = ENV["SHOPIFY_ADMIN_ACCESS_TOKEN"]
    secret      = ENV["SHOPIFY_API_SECRET"]
    if shop_domain.present? && token.present? && secret.present?
      ok.call("Shopify env configured (#{shop_domain})")
    else
      missing = []
      missing << "SHOPIFY_SHOP_DOMAIN" if shop_domain.blank?
      missing << "SHOPIFY_ADMIN_ACCESS_TOKEN" if token.blank?
      missing << "SHOPIFY_API_SECRET" if secret.blank?
      warn.call("Shopify env incomplete (missing: #{missing.join(', ')}) — OK for dev without a store")
    end

    puts "──────────────────────────────────────────────"
    if exit_code.zero?
      puts "  \e[32mAll critical checks passed.\e[0m"
    else
      puts "  \e[31mOne or more critical checks failed.\e[0m"
    end
    puts ""
    exit(exit_code)
  end
end
