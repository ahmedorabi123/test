class RefundPolicy < ApplicationPolicy
  def resource_name = "orders"

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
