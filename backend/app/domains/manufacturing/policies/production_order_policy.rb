class ProductionOrderPolicy < ApplicationPolicy
  def resource_name = "production_orders"

  def run?    = admin_or_can?(:write)
  def cancel? = admin_or_can?(:write)

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
