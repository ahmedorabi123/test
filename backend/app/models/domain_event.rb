class DomainEvent < ApplicationRecord
  validates :aggregate_type, :aggregate_id, :event_type, :occurred_at, presence: true

  scope :undispatched, -> { where(dispatched_at: nil) }

  def dispatched?
    dispatched_at.present?
  end

  def self.append(aggregate:, event_type:, payload: {})
    create!(
      aggregate_type: aggregate.class.name,
      aggregate_id:   aggregate.id,
      event_type:     event_type.to_s,
      payload:        payload,
      occurred_at:    Time.current
    )
  end
end
