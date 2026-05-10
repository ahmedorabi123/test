# Auto-run the Shopify bootstrap in development on first server start.
#
# In production, bootstrap is triggered by puma.rb's on_worker_boot hook
# (which only fires in cluster mode). In development Rails runs puma in
# single mode, so on_worker_boot never fires — this initializer fills that gap.
#
# The bootstrap is fully idempotent: it checks local vs remote counts and
# skips any entity whose local count already matches Shopify. So running it
# on every server restart is safe and very fast after the first pull.
#
# Disable with SKIP_BOOTSTRAP=true.

return if Rails.env.test?
return if %w[true 1].include?(ENV["SKIP_BOOTSTRAP"].to_s.downcase)
return unless Rails.env.development?
return unless defined?(Rails::Server)
return unless ENV["SHOPIFY_SHOP_DOMAIN"].present? && ENV["SHOPIFY_ADMIN_ACCESS_TOKEN"].present?

Thread.new do
  sleep 3  # Let Rails finish booting before hitting the DB

  begin
    require "rake"
    Rails.application.load_tasks unless Rake::Task.task_defined?("bootstrap:run")

    Rails.application.executor.wrap do
      Rake::Task["bootstrap:run"].reenable rescue nil
      Rake::Task["bootstrap:run"].invoke
    end
  rescue => e
    Rails.logger.error("[bootstrap] dev auto-run failed: #{e.class}: #{e.message}")
    warn "[bootstrap] dev auto-run failed: #{e.class}: #{e.message}"
  end
end
