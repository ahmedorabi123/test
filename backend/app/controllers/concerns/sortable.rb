# Mixes sorting into an API controller.
#
# Usage:
#   class ProductsController < ApplicationController
#     include Sortable
#     sortable_by :title, :vendor, :status, :updated_at, default: { updated_at: :desc }
#   end
#
# Query params:
#   ?sort=title&dir=asc   => .order(title: :asc)
#   ?sort=title           => :asc assumed
#
# Unknown keys fall back to the default.
module Sortable
  extend ActiveSupport::Concern

  class_methods do
    def sortable_by(*keys, default: nil)
      @sortable_keys = keys.map(&:to_s)
      @sortable_default = default
    end

    def sortable_keys = @sortable_keys || []
    def sortable_default = @sortable_default
  end

  # Apply sort to a scope using request params.
  def apply_sort(scope)
    keys    = self.class.sortable_keys
    default = self.class.sortable_default
    req_key = params[:sort].to_s
    req_dir = params[:dir].to_s.downcase == "desc" ? :desc : :asc

    if keys.include?(req_key)
      scope.order(req_key => req_dir)
    elsif default.is_a?(Hash)
      scope.order(default)
    else
      scope
    end
  end
end
