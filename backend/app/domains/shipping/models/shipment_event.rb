class ShipmentEvent < ApplicationRecord
  belongs_to :fulfillment, inverse_of: :shipment_events
  belongs_to :actor, class_name: "User", optional: true

  validates :kind, presence: true
end