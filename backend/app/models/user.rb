class User < ApplicationRecord
  include Devise::JWT::RevocationStrategies::JTIMatcher

  devise :database_authenticatable,
         :recoverable,
         :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :role_permissions, through: :roles
  has_many :permissions, through: :role_permissions

  validates :first_name, :last_name, presence: true
  validates :email, presence: true, uniqueness: { case_sensitive: false }

  scope :active, -> { where(active: true) }

  def full_name
    "#{first_name} #{last_name}"
  end

  def can?(resource, action)
    permissions.exists?(resource: resource.to_s, action: action.to_s)
  end

  def admin?
    roles.exists?(name: "admin")
  end
end
