class ChangeDomainEventsAggregateIdToString < ActiveRecord::Migration[8.0]
  def up
    # Table is currently empty (feature not yet live) so in-place type change is safe.
    safety_assured { change_column :domain_events, :aggregate_id, :string }
  end

  def down
    safety_assured do
      execute "ALTER TABLE domain_events ALTER COLUMN aggregate_id TYPE uuid USING aggregate_id::uuid"
    end
  end
end
