module PolicyHelpers
  # Create a user that has only the given permission keys (resource:action).
  def user_with_permissions(*keys)
    user = create(:user)
    role = Role.create!(name: "spec_role_#{SecureRandom.hex(4)}", description: "spec")
    user.roles << role
    keys.each do |key|
      resource, action = key.to_s.split(":")
      perm = Permission.find_or_create_by!(resource: resource, action: action)
      RolePermission.find_or_create_by!(role: role, permission: perm)
    end
    user
  end

  def admin_user
    create(:user, :admin)
  end

  def viewer_user
    user_with_permissions
  end
end

RSpec.configure do |c|
  c.include PolicyHelpers, type: :policy
  c.include PolicyHelpers, file_path: %r{spec/policies}
end
