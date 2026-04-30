class WebhookEvent < ApplicationRecord
  validates :source, :topic, :external_id, :received_at, presence: true
  validates :external_id, uniqueness: { scope: :source }

  scope :unprocessed, -> { where(processed_at: nil) }
  scope :failed,      -> { where.not(error: nil) }

  def processed?
    processed_at.present?
  end

  def mark_processed!
    update!(processed_at: Time.current, error: nil)
  end

  def mark_failed!(message)
    update!(error: message, attempts: attempts + 1)
  end
end
