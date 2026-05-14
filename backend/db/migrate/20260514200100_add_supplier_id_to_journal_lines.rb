class AddSupplierIdToJournalLines < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      add_reference :journal_lines, :supplier, type: :uuid, null: true, index: true, foreign_key: { to_table: :suppliers }
    end
  end

  def down
    safety_assured do
      remove_reference :journal_lines, :supplier, foreign_key: { to_table: :suppliers }, index: true
    end
  end
end
