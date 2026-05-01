# Failsafe: guarantee the login users always exist in the database.
#
# Runs on every server boot (all environments except test). If users,
# roles, or permissions are missing for any reason (fresh volume, reset DB,
# failed seed), this recreates them before the first request is served.
#
# This is intentionally silent on success — it only logs when it acts.

return if Rails.env.test?

Rails.application.config.after_initialize do
  Thread.new do
    begin
      # Give ActiveRecord connection pool a moment after boot
      sleep 1

      Rails.application.executor.wrap do
        next unless ActiveRecord::Base.connection.table_exists?(:users)
        next unless ActiveRecord::Base.connection.table_exists?(:roles)
        next unless ActiveRecord::Base.connection.table_exists?(:permissions)

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

        Rails.logger.warn("[ensure_login_users] #{missing.size} login user(s) missing — recreating...")

        # Ensure permissions exist first
        if Permission.count.zero?
          Permission::ALL.each do |key|
            resource, action = key.split(":")
            Permission.find_or_create_by!(resource: resource, action: action)
          end
        end

        all_permissions = Permission.all.to_a

        # Ensure all roles exist
        role_map = {
          "admin"         => { desc: "Full access to all modules",             perms: all_permissions },
          "operations"    => { desc: "Manage orders, fulfillments, inventory", perms: Permission.where(resource: %w[orders fulfillments customers products inventory stock_transfers warehouses]).to_a },
          "showroom_clerk"=> { desc: "Create showroom orders and view stock",  perms: Permission.where(resource: %w[orders customers inventory], action: %w[read write]).to_a },
          "accountant"    => { desc: "View and post accounting entries",       perms: Permission.where(resource: %w[accounting orders fulfillments customers]).to_a },
          "viewer"        => { desc: "Read-only access to all modules",        perms: Permission.where(action: "read").to_a },
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
        end

        Rails.logger.warn("[ensure_login_users] Done.")
      end
    rescue => e
      Rails.logger.error("[ensure_login_users] Failed: #{e.class}: #{e.message}")
    end
  end
end
