class PurchaseOrderPolicy < ApplicationPolicy
  def resource_name = "purchase_orders"

  def receive? = admin_or_can?(:receive) || admin_or_can?(:write)
  def approve? = admin_or_can?(:approve) || admin_or_can?(:write)

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
