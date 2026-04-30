class Permission < ApplicationRecord
  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions

  validates :resource, :action, presence: true
  validates :action, uniqueness: { scope: :resource }

  # Full permission set for the ERP — "resource:action"
  ALL = %w[
    users:read        users:write       users:delete
    roles:read        roles:write
    customers:read    customers:write
    products:read     products:write
    orders:read       orders:write      orders:cancel     orders:refund     orders:export
    fulfillments:read fulfillments:write
    inventory:read    inventory:write   inventory:adjust
    warehouses:read   warehouses:write
    stock_transfers:read  stock_transfers:write
    suppliers:read    suppliers:write
    purchase_orders:read  purchase_orders:write  purchase_orders:approve  purchase_orders:receive
    accounting:read   accounting:write  accounting:post
    settings:read     settings:write
  ].freeze
end
