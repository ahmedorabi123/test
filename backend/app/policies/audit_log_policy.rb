class AuditLogPolicy < ApplicationPolicy
  def resource_name = "settings"

  def index? = user.admin?

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
