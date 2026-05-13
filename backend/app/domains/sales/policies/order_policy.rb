class OrderPolicy < ApplicationPolicy
  def resource_name = "orders"

  def cancel?     = admin_or_can?(:cancel) && !shopify_locked?
  def refund?     = admin_or_can?(:refund) && !shopify_locked?
  def export?     = admin_or_can?(:export)
  def transition? = admin_or_can?(:write) || admin_or_can?(:update)
  def update?     = admin_or_can?(:write)

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
