class FulfillmentPolicy < ApplicationPolicy
  # Shipments are read-only in the UI; writes happen via Shopify webhooks
  # or future Bosta adapter, so we reuse "orders" resource for RBAC.
  def resource_name = "orders"

  def transition_delivery?
    admin_or_can?(:write)
  end

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
