# Failsafe: guarantee the login users always exist in the database.
#
# Runs SYNCHRONOUSLY on every Rails server boot (all environments except
# test), BEFORE Puma starts accepting requests. If users, roles, or
# permissions are missing for any reason (fresh volume, reset DB, failed
# seed, partial migration, dropped users), this recreates them now.
#
# History: a previous async (Thread.new + sleep) version raced with the
# first request and silently swallowed errors, repeatedly leaving the app
# un-loginable on fresh volumes. NEVER reintroduce a Thread.new here.
#
# Idempotent — silent on success, only logs when it acts.

return if Rails.env.test?
return if ENV["SKIP_ENSURE_LOGIN_USERS"] == "true"

# Skip when running rake / console / runner / dbconsole / generators —
# those don't serve HTTP and may run before migrations finish. We want
# this to run during a real server boot (rails s, puma, rails server).
prog = $PROGRAM_NAME.to_s
return if prog.end_with?("rake") || prog.end_with?("rails")  &&
          (ARGV.first.to_s =~ /\A(console|runner|dbconsole|generate|destroy|new|db:|assets:|webpacker:|test|spec)/)
return if defined?(Rake) && Rake.respond_to?(:application) && Rake.application.top_level_tasks.any?
return if defined?(Rails::Console)

Rails.application.config.after_initialize do
  begin
    next unless ActiveRecord::Base.connection.data_source_exists?("users")
    next unless ActiveRecord::Base.connection.data_source_exists?("roles")
    next unless ActiveRecord::Base.connection.data_source_exists?("permissions")

    admin_email    = ENV.fetch("ADMIN_EMAIL",    "admin@erp.local")
    admin_password = ENV.fetch("ADMIN_PASSWORD", "changeme123!")

    login_users = [
      { email: admin_email,            password: admin_password,  first_name: "ERP",    last_name: "Admin",   role_name: "admin" },
      { email: "ops@erp.local",        password: "changeme123!",  first_name: "Oliver", last_name: "Ops",     role_name: "operations" },
      { email: "viewer@erp.local",     password: "changeme123!",  first_name: "Vera",   last_name: "Viewer",  role_name: "viewer" },
      { email: "accountant@erp.local", password: "changeme123!",  first_name: "Alan",   last_name: "Counts",  role_name: "accountant" },
    ]

    missing = login_users.reject { |u| User.exists?(email: u[:email]) }
    next if missing.empty?

    Rails.logger.warn("[ensure_login_users] #{missing.size} login user(s) missing — recreating synchronously before serving requests...")
    warn "[ensure_login_users] #{missing.size} login user(s) missing — recreating..."

    if Permission.count.zero?
      Permission::ALL.each do |key|
        resource, action = key.split(":")
        Permission.find_or_create_by!(resource: resource, action: action)
      end
    end

    all_permissions = Permission.all.to_a

    role_map = {
      "admin"          => { desc: "Full access to all modules",             perms: all_permissions },
      "operations"     => { desc: "Manage orders, fulfillments, inventory", perms: Permission.where(resource: %w[orders fulfillments customers products inventory stock_transfers warehouses]).to_a },
      "showroom_clerk" => { desc: "Create showroom orders and view stock",  perms: Permission.where(resource: %w[orders customers inventory], action: %w[read write]).to_a },
      "accountant"     => { desc: "View and post accounting entries",       perms: Permission.where(resource: %w[accounting orders fulfillments customers]).to_a },
      "viewer"         => { desc: "Read-only access to all modules",        perms: Permission.where(action: "read").to_a },
    }

    role_map.each do |name, cfg|
      role = Role.find_or_create_by!(name: name) { |r| r.description = cfg[:desc] }
      role.permissions = cfg[:perms] if role.permissions.empty?
    end

    missing.each do |attrs|
      role = Role.find_by!(name: attrs[:role_name])
      u = User.find_or_initialize_by(email: attrs[:email])
      u.assign_attributes(
        first_name: attrs[:first_name],
        last_name:  attrs[:last_name],
        password:   attrs[:password],
        active:     true
      )
      u.save!
      u.user_roles.find_or_create_by!(role: role)
      Rails.logger.warn("[ensure_login_users]   created #{attrs[:email]}")
      warn "[ensure_login_users]   created #{attrs[:email]}"
    end

    Rails.logger.warn("[ensure_login_users] Done — #{User.count} user(s) ready.")
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished => e
    Rails.logger.warn("[ensure_login_users] DB not ready (#{e.class}); skipping. Will retry next boot.")
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.warn("[ensure_login_users] Schema not ready (#{e.class}: #{e.message}); skipping.")
  rescue => e
    # LOUD failure — do NOT swallow. We'd rather fail boot than serve a
    # broken login surface and have the user hit "no_user" repeatedly.
    Rails.logger.error("[ensure_login_users] FAILED: #{e.class}: #{e.message}")
    warn "[ensure_login_users] FAILED: #{e.class}: #{e.message}"
    warn e.backtrace.first(10).join("\n")
    raise
  end
end
