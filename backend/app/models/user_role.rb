class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  # warehouse_id can scope showroom_clerk to a specific warehouse

  validates :user_id, uniqueness: { scope: %i[role_id warehouse_id] }
end
