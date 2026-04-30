class UserPolicy < ApplicationPolicy
  def resource_name = "users"

  # Only admins can manage users
  def index?   = user.admin?
  def show?    = user.admin? || user.id == record.id
  def create?  = user.admin?
  def update?  = user.admin? || user.id == record.id
  def destroy? = user.admin? && user.id != record.id

  class Scope < ApplicationPolicy::Scope
    def resolve
      user.admin? ? scope.all : scope.where(id: user.id)
    end
  end
end
