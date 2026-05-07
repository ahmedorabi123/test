class CollectionPolicy < ApplicationPolicy
  # Reuses the products permission resource since collections are part of
  # the catalog module.
  def resource_name = "products"

  class Scope < Scope
    def resolve = scope.all
  end
end
