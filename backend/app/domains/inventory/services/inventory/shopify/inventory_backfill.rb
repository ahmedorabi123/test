# Backfill all Shopify inventory_levels into StockItem.
#
# Strategy:
#   1. Fetch /admin/api/.../locations.json
#   2. For each location → /admin/api/.../inventory_levels.json?location_ids=<id>
#   3. Feed each level into Inventory::Shopify::StockSyncService (which finds
#      the variant by shopify_inventory_item_id and matching warehouse).
#
# Returns counts: { locations:, levels:, applied:, skipped:, errors: }.
class Inventory::Shopify::InventoryBackfill
  def self.call
    new.call
  end

  def initialize
    @client = ::Shopify::Client.new
    @stats  = { locations: 0, levels: 0, applied: 0, skipped: 0, errors: 0 }
  end

  def call
    locations = @client.get("locations.json")["locations"] || []
    @stats[:locations] = locations.size

    locations.each do |loc|
      sync_location(loc)
    end

    @stats
  end

  private

  def sync_location(loc)
    location_id = loc["id"]
    code = "SHOPIFY-#{location_id}"
    # Ensure a warehouse exists for this Shopify location. Match by either
    # shopify_location_id OR code (older webhook-created rows may have only the code).
    wh = Warehouse.where(shopify_location_id: location_id).or(Warehouse.where(code: code)).first
    if wh
      wh.update!(shopify_location_id: location_id) if wh.shopify_location_id.blank?
    else
      Warehouse.create!(
        shopify_location_id: location_id,
        code:                code,
        name:                loc["name"].presence || "Shopify Location #{location_id}",
        kind:                "own"
      )
    end

    @client.paginated("inventory_levels.json", key: "inventory_levels",
                      params: { location_ids: location_id }).each do |lvl|
      @stats[:levels] += 1
      begin
        result = Inventory::Shopify::StockSyncService.call(lvl)
        result ? (@stats[:applied] += 1) : (@stats[:skipped] += 1)
      rescue StandardError => e
        @stats[:errors] += 1
        Rails.logger.warn "[InventoryBackfill] level=#{lvl.inspect[0, 120]}: #{e.message}"
      end
    end
  end
end
