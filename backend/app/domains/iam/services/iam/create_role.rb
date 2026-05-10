module Iam
  # Atomically creates a Role with the given permission keys ("resource:action").
  # Validates that every key is part of Permission::ALL.
  class CreateRole
    Result = Struct.new(:role, :error, keyword_init: true) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(name:, description: nil, permission_keys: [])
      @name = name.to_s.strip
      @description = description
      @permission_keys = Array(permission_keys).map(&:to_s).uniq
    end

    def call
      return Result.new(error: "Name is required") if @name.blank?

      invalid = @permission_keys - Permission::ALL
      return Result.new(error: "Unknown permissions: #{invalid.join(", ")}") if invalid.any?

      role = nil
      ActiveRecord::Base.transaction do
        role = Role.create!(name: @name, description: @description)
        sync_permissions!(role)
      end
      Result.new(role: role)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(error: e.record.errors.full_messages.join(", "))
    end

    private

    def sync_permissions!(role)
      return if @permission_keys.empty?

      perms = @permission_keys.map do |key|
        resource, action = key.split(":", 2)
        Permission.find_or_create_by!(resource: resource, action: action)
      end
      role.permissions = perms
    end
  end
end
