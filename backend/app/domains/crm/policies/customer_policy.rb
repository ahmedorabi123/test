class CustomerPolicy < ApplicationPolicy
  def resource_name = "customers"

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
