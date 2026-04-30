class WarehousePolicy < ApplicationPolicy
  def resource_name = "warehouses"

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
