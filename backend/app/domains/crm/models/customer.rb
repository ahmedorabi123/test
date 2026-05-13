class Customer < ApplicationRecord
  include Shopify::Origin

  SOURCES = %w[manual shopify].freeze

  shopify_origin_via :shopify_customer_id

  has_many :orders, inverse_of: :customer, dependent: :nullify

  validates :email, uniqueness: { case_sensitive: false, allow_blank: true }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true }
  validates :currency, presence: true, length: { is: 3 }
  validates :source, inclusion: { in: SOURCES }
  validate  :email_or_phone_present

  scope :shopify_linked, -> { where.not(shopify_customer_id: nil) }

  before_validation :default_currency

  def full_name
    [first_name, last_name].compact_blank.join(" ").presence
  end

  def display_name
    full_name || email || phone || "Customer #{id}"
  end

  # Returns the most recent persisted order placed by this customer, if any.
  def last_order
    @last_order ||= orders.order(placed_at: :desc).first
  end

  private

  def default_currency
    self.currency = (currency.presence || "EGP").upcase
  end

  def email_or_phone_present
    return if email.present? || phone.present?

    errors.add(:base, "Email or phone is required")
  end
end
