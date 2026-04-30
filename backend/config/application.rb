require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Backend
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true

    # Autoload domain folders — each subfolder of app/domains/* acts like app/
    config.autoload_paths += Dir[Rails.root.join("app/domains/*/models")]
    config.autoload_paths += Dir[Rails.root.join("app/domains/*/services")]
    config.autoload_paths += Dir[Rails.root.join("app/domains/*/handlers")]
    config.autoload_paths += Dir[Rails.root.join("app/domains/*/policies")]
    config.autoload_paths += Dir[Rails.root.join("app/domains/*/serializers")]
    config.autoload_paths += Dir[Rails.root.join("app/domains/*/providers")]
    config.autoload_paths += Dir[Rails.root.join("app/domains/shared")]
    config.autoload_paths += Dir[Rails.root.join("app/domains/integrations")]
    config.autoload_paths += Dir[Rails.root.join("app/domains/shipping")]
    config.autoload_paths += Dir[Rails.root.join("app/domains/shipping/providers")]

    config.autoload_lib(ignore: %w[assets tasks])

    # Default timezone (UTC stored, Cairo rendered in frontend)
    config.time_zone = "UTC"

    # Enforce strong migrations
    config.active_record.migration_error = :page_load

    # Use Sidekiq for background jobs
    config.active_job.queue_adapter = :sidekiq

    # Structured logging (SemanticLogger)
    config.log_level = :info

    # Devise-jwt requires cookie/session middleware even in API-only mode.
    # Sessions are never actually used for auth (JWT handles that), but Warden
    # needs the session store to exist during sign_in.
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
                          key: "_erp_session",
                          same_site: :lax,
                          secure: Rails.env.production?
  end
end
