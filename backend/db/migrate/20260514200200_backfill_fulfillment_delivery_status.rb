class BackfillFulfillmentDeliveryStatus < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  # Maps the legacy `fulfillments.status` field to the canonical
  # `delivery_status` used by the Phase 1 shipment filters.
  STATUS_MAP = {
    "failure" => "failed",
    "success" => "delivered",
    "open"    => "in_transit",
    "pending" => "pending"
  }.freeze

  def up
    safety_assured do
      STATUS_MAP.each do |old_status, new_status|
        execute <<~SQL.squish
          UPDATE fulfillments
             SET delivery_status = '#{new_status}'
           WHERE delivery_status IS NULL
             AND status = '#{old_status}'
        SQL
      end
    end
  end

  def down
    # No-op — the column already existed and the original `status` is unchanged.
  end
end
