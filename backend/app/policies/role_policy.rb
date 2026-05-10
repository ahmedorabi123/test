class RolePolicy < ApplicationPolicy
  def resource_name = "roles"
  def index?   = user.admin? || user.can?("roles", "read")
  def show?    = index?
  def create?  = user.admin?
  def update?  = user.admin?
  def destroy? = user.admin?
end
