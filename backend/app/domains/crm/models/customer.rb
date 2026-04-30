class Customer < ApplicationRecord
  has_many :orders, inverse_of: :customer, dependent: :nullify

  validates :email, uniqueness: { case_sensitive: false, allow_blank: true }

  scope :shopify_linked, -> { where.not(shopify_customer_id: nil) }

  def full_name
    [first_name, last_name].compact_blank.join(" ").presence
  end

  def display_name
    full_name || email || phone || "Customer #{id}"
  end
end
