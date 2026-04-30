class CreateAccountingDomain < ActiveRecord::Migration[8.0]
  def change
    # ── Chart of Accounts ──────────────────────────────────────────────────
    create_table :accounts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :code,        null: false         # e.g. "1100"
      t.string   :name,        null: false         # e.g. "Accounts Receivable"
      t.string   :account_type, null: false        # asset|liability|equity|revenue|expense
      t.string   :normal_side,  null: false        # debit|credit
      t.text     :description
      t.boolean  :active,      null: false, default: true
      t.string   :currency,    null: false, default: "EGP"
      # parent for account tree (optional grouping)
      t.references :parent, type: :uuid, foreign_key: { to_table: :accounts }, null: true
      t.timestamps
    end
    add_index :accounts, :code, unique: true
    add_index :accounts, :account_type

    # ── Journal Entries (header) ─────────────────────────────────────────────
    create_table :journal_entries, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.date     :entry_date,   null: false
      t.string   :description,  null: false
      # posted | draft | reversed
      t.string   :status,       null: false, default: "posted"
      t.string   :currency,     null: false, default: "EGP"
      # source linkage (polymorphic-ish — just strings)
      t.string   :source_type                      # "order" | "refund" | "manual"
      t.string   :source_id                        # uuid of the source record
      # idempotency — one journal per (source_type, source_id, entry_type)
      t.string   :entry_type                       # "sale" | "refund" | "manual" etc.
      t.string   :idempotency_key                  # prevents double-posting
      # reversal link
      t.references :reversal_of, type: :uuid,
                   foreign_key: { to_table: :journal_entries }, null: true
      t.timestamps
    end
    add_index :journal_entries, :idempotency_key, unique: true,
              where: "idempotency_key IS NOT NULL"
    add_index :journal_entries, %i[source_type source_id]
    add_index :journal_entries, :entry_date
    add_index :journal_entries, :status

    # ── Journal Lines (debit / credit splits) ───────────────────────────────
    create_table :journal_lines, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :journal_entry, null: false, type: :uuid, foreign_key: true
      t.references :account,       null: false, type: :uuid, foreign_key: true
      t.string   :side,   null: false             # "debit" | "credit"
      t.decimal  :amount, precision: 15, scale: 2, null: false
      t.string   :currency, null: false, default: "EGP"
      t.text     :description
      t.timestamps
    end
    add_index :journal_lines, :side
    add_index :journal_lines, %i[account_id side]

    # DB-level check: SUM(debits) = SUM(credits) per entry is enforced in the
    # model/service — Postgres CHECK across aggregate is not easily done here,
    # but we ensure it in JournalEntry#post! via a before_save validation.
  end
end
