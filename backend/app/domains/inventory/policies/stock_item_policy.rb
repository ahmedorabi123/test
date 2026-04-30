class StockItemPolicy < ApplicationPolicy
  def resource_name = "stock_items"

  class Scope < ApplicationPolicy::Scope
    def resolve = scope.all
  end
end
