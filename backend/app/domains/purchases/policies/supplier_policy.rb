class SupplierPolicy < ApplicationPolicy
  def resource_name = "suppliers"

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
