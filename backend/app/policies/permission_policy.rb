class PermissionPolicy < ApplicationPolicy
  def resource_name = "permissions"
  def index? = user.admin? || user.can?("roles", "read")
end
