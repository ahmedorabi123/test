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
  #
  # Adds NULLS LAST so columns like `last_order_at` / `total_spent` don't
  # surface a wall of NULL rows on `desc`.
  #
  # Special case: when sorting by `order_number` on the orders table, we
  # actually sort by `placed_at` (chronological). The order number stored
  # on disk is a string like "SO-202605-A1B2C3D4" whose lexicographic
  # ordering does NOT match issuance order; sorting on it produced
  # nonsense. Shopify's "Order #" column is also chronological under the
  # hood, so this matches user expectation.
  def apply_sort(scope)
    keys    = self.class.sortable_keys
    default = self.class.sortable_default
    req_key = params[:sort].to_s
    req_dir = params[:dir].to_s.downcase == "desc" ? :desc : :asc

    if keys.include?(req_key)
      table_name = scope.respond_to?(:table_name) ? scope.table_name : scope.klass.table_name
      effective_key = sort_alias(table_name, req_key)
      qualified  = "#{table_name}.#{effective_key}"
      scope.order(Arel.sql("#{qualified} #{req_dir.to_s.upcase} NULLS LAST, #{table_name}.id #{req_dir.to_s.upcase}"))
    elsif default.is_a?(Hash)
      scope.order(default)
    else
      scope
    end
  end

  # Map a requested sort key to the actual sortable column.
  # Subclasses can override or the table-aware default below applies.
  def sort_alias(table_name, key)
    return "placed_at" if table_name == "orders" && key == "order_number"
    return "last_delivery_status" if table_name == "orders" && key == "delivery_status"

    key
  end
end
