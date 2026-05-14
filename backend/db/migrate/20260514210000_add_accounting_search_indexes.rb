class AddAccountingSearchIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    # pg_trgm powers fast ILIKE %substring% searches on description fields.
    safety_assured { enable_extension "pg_trgm" } if respond_to?(:safety_assured)
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_index :journal_entries, :description,
      using: :gin,
      opclass: { description: :gin_trgm_ops },
      name: "index_journal_entries_on_description_trgm",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :journal_lines, :description,
      using: :gin,
      opclass: { description: :gin_trgm_ops },
      name: "index_journal_lines_on_description_trgm",
      algorithm: :concurrently,
      if_not_exists: true

    add_index :journal_lines, :amount,
      name: "index_journal_lines_on_amount",
      algorithm: :concurrently,
      if_not_exists: true
  end

  def down
    remove_index :journal_lines, name: "index_journal_lines_on_amount", if_exists: true
    remove_index :journal_lines, name: "index_journal_lines_on_description_trgm", if_exists: true
    remove_index :journal_entries, name: "index_journal_entries_on_description_trgm", if_exists: true
  end
end
