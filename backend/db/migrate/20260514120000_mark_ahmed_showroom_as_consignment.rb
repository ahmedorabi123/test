class MarkAhmedShowroomAsConsignment < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      execute <<~SQL.squish
        UPDATE warehouses
        SET kind = 'consignment', updated_at = CURRENT_TIMESTAMP
        WHERE LOWER(name) = 'ahmed' AND kind <> 'consignment'
      SQL
    end
  end

  def down
    # Data-only correction; do not guess the previous warehouse kind.
  end
end