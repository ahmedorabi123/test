class CreateAuditLogs < ActiveRecord::Migration[8.0]
  def change
    create_table :audit_logs, id: :uuid do |t|
      t.uuid    :user_id
      t.string  :action,       null: false
      t.string  :subject_type, null: false
      t.uuid    :subject_id
      t.jsonb   :diff,         default: {}
      t.string  :ip_address
      t.string  :user_agent
      t.datetime :occurred_at, null: false, default: -> { "NOW()" }
      t.timestamps
    end
    add_index :audit_logs, :user_id
    add_index :audit_logs, %i[subject_type subject_id]
    add_index :audit_logs, :occurred_at
  end
end
