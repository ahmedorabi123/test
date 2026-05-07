require "spec_helper"
# Force test environment regardless of the container's RAILS_ENV variable.
# This ensures rspec ALWAYS runs against erp_test (never erp_development),
# keeping Shopify/UI data completely isolated from the test suite.
ENV["RAILS_ENV"] = "test"
require_relative "../config/environment"
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
require "database_cleaner/active_record"
require "shoulda/matchers"
require "webmock/rspec"

# Load support files
Rails.root.glob("spec/support/**/*.rb").sort_by(&:to_s).each { |f| require f }

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.fixture_paths = [ Rails.root.join("spec/fixtures") ]
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  # FactoryBot
  config.include FactoryBot::Syntax::Methods

  # DatabaseCleaner
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning { example.run }
  end

  # Helpers available in request specs
  config.include RequestSpecHelpers, type: :request

  # rspec-rails' default host `www.example.com` isn't in Rails 8's default
  # `config.hosts` whitelist. Override it to `localhost` which matches `.localhost`.
  config.before(:each, type: :request) { host! "localhost" }

  # ActiveJob test adapter so `have_enqueued_job` and `perform_enqueued_jobs` work.
  config.before(:each) do
    ActiveJob::Base.queue_adapter = :test
  end
  config.include ActiveJob::TestHelper
end

Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end
