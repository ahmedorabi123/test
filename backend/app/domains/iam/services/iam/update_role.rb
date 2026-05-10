module Iam
  # Atomically updates a Role's name/description and replaces its permission set.
  # Validates that every permission key is part of Permission::ALL.
  # Renaming a system role is rejected.
  class UpdateRole
    Result = Struct.new(:role, :error, keyword_init: true) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(role:, name: nil, description: nil, permission_keys: nil)
      @role = role
      @name = name&.to_s&.strip
      @description = description
      @permission_keys = permission_keys.nil? ? nil : Array(permission_keys).map(&:to_s).uniq
    end

    def call
      if @name && @name != @role.name && Role::SYSTEM_ROLES.include?(@role.name)
        return Result.new(error: "Cannot rename system role '#{@role.name}'")
      end

      if @permission_keys
        invalid = @permission_keys - Permission::ALL
        return Result.new(error: "Unknown permissions: #{invalid.join(", ")}") if invalid.any?
      end

      ActiveRecord::Base.transaction do
        attrs = {}
        attrs[:name]        = @name        if @name
        attrs[:description] = @description unless @description.nil?
        @role.update!(attrs) if attrs.any?
        sync_permissions!(@role) if @permission_keys
      end
      Result.new(role: @role.reload)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(error: e.record.errors.full_messages.join(", "))
    end

    private

    def sync_permissions!(role)
      perms = @permission_keys.map do |key|
        resource, action = key.split(":", 2)
        Permission.find_or_create_by!(resource: resource, action: action)
      end
      role.permissions = perms
    end
  end
end
