class ProductPolicy < ApplicationPolicy
  def resource_name = "products"

  class Scope < Scope
    def resolve
      scope.all
    end
  end
end
