class AuditLog < ApplicationRecord
  belongs_to :user, optional: true

  validates :action, :subject_type, presence: true

  def self.record(user:, action:, subject:, diff: {}, request: nil)
    create!(
      user_id:      user&.id,
      action:       action.to_s,
      subject_type: subject.class.name,
      subject_id:   subject.id,
      diff:         diff,
      ip_address:   request&.remote_ip,
      user_agent:   request&.user_agent,
      occurred_at:  Time.current
    )
  end
end
