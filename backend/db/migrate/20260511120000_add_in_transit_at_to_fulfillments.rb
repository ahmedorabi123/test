class AddInTransitAtToFulfillments < ActiveRecord::Migration[8.0]
  def change
    add_column :fulfillments, :in_transit_at, :datetime unless column_exists?(:fulfillments, :in_transit_at)
  end
end
