class ChangeActiveStorageAttachmentsRecordIdToString < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      change_column :active_storage_attachments, :record_id, :string
    end
  end

  def down
    safety_assured do
      change_column :active_storage_attachments, :record_id, :bigint, using: "record_id::bigint"
    end
  end
end