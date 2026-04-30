class AccountingPolicy < ApplicationPolicy
  def resource_name = "accounting"

  class Scope < Scope
    def resolve = scope.all
  end
end
