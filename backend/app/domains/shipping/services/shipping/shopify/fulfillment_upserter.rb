module Shipping
  module Shopify
    # Upserts a Shopify fulfillments/create|update webhook payload into our
    # Fulfillment model and — on first insert of a successful fulfillment —
    # writes negative stock movements for each fulfilled line item.
    #
    # Payload shape (Shopify):
    #   {
    #     "id" => 12345, "order_id" => 98765, "status" => "success",
    #     "tracking_company" => "Bosta", "tracking_number" => "BST-1",
    #     "tracking_url" => "https://...", "location_id" => 111,
    #     "created_at" => "...", "updated_at" => "...",
    #     "line_items" => [ { "id" => ..., "quantity" => 2, "variant_id" => ... } ]
    #   }
    class FulfillmentUpserter
      def self.call(payload)
        new(payload).call
      end

      def initialize(payload)
        @payload = payload.with_indifferent_access
      end

      def call
        shopify_id = @payload[:id].to_i
        order = find_order
        return nil unless order

        ActiveRecord::Base.transaction do
          fulfillment = ::Fulfillment.find_or_initialize_by(shopify_fulfillment_id: shopify_id)
          was_new        = fulfillment.new_record?
          was_successful = !was_new && fulfillment.status == "success"

          fulfillment.assign_attributes(
            order:              order,
            location_id:        @payload[:location_id].presence&.to_i,
            status:             map_status,
            tracking_company:   @payload[:tracking_company].presence,
            tracking_number:    @payload[:tracking_number].presence,
            tracking_url:       @payload[:tracking_url].presence,
            delivery_status:    @payload[:shipment_status].presence || @payload[:delivery_status].presence,
            service:            @payload[:service].presence || infer_service(@payload[:tracking_company]),
            shipped_at:         parse_time(@payload[:created_at]),
            delivered_at:       (@payload[:shipment_status].to_s == "delivered" ? parse_time(@payload[:updated_at]) : nil),
            shopify_updated_at: parse_time(@payload[:updated_at])
          )
          fulfillment.save!
          sync_line_items(fulfillment)

          # Only deduct inventory the first time this fulfillment becomes successful.
          if fulfillment.status == "success" && (was_new || !was_successful)
            deduct_inventory(fulfillment)
            post_cogs_journal(fulfillment)
          end

          # Keep the order fulfillment_status in sync (doesn't alter financial state).
          order.update!(
            fulfillment_status: "fulfilled",
            status:             order.status == "pending" ? "fulfilled" : order.status
          ) if fulfillment.status == "success" && order.fulfillment_status != "fulfilled"

          fulfillment
        end
      end

      private

      def find_order
        order_id = @payload[:order_id].to_i
        return nil if order_id.zero?
        ::Order.find_by(shopify_order_id: order_id)
      end

      def map_status
        val = @payload[:status].to_s
        ::Fulfillment::STATUSES.include?(val) ? val : "success"
      end

      def infer_service(company)
        return nil if company.blank?
        c = company.to_s.downcase
        return "bosta"  if c.include?("bosta")
        return "aramex" if c.include?("aramex")
        return "dhl"    if c.include?("dhl")
        nil
      end

      def sync_line_items(fulfillment)
        incoming = Array(@payload[:line_items])
        keep_ids = []
        incoming.each do |li|
          lh = li.with_indifferent_access
          shopify_line_id = lh[:id].to_i
          oli = fulfillment.order.line_items.find_by(shopify_line_item_id: shopify_line_id)
          row = fulfillment.fulfillment_line_items.find_or_initialize_by(shopify_line_item_id: shopify_line_id)
          row.order_line_item = oli
          row.quantity        = [lh[:quantity].to_i, 1].max
          row.save!
          keep_ids << row.id
        end
        fulfillment.fulfillment_line_items.where.not(id: keep_ids).destroy_all if incoming.any?
      end

      def deduct_inventory(fulfillment)
        fallback_wh = ::Inventory::WarehouseResolver.primary
        warehouse   = ::Inventory::WarehouseResolver.for_shopify_location(
          fulfillment.location_id, fallback: fallback_wh
        ) || fallback_wh

        return unless warehouse

        fulfillment.fulfillment_line_items.each do |fli|
          variant = fli.order_line_item&.variant
          next unless variant

          stock_item = ::StockItem.find_or_create_by!(variant: variant, warehouse: warehouse) do |si|
            si.quantity_on_hand = 0
          end

          ::Inventory::WriteMovement.call(
            stock_item: stock_item,
            delta:      -fli.quantity,
            reason:     "fulfilled",
            reference:  fulfillment
          )
        end
      end

      def post_cogs_journal(fulfillment)
        ::Accounting::PostCogsHandler.call(fulfillment)
      rescue StandardError => e
        Rails.logger.warn "[FulfillmentUpserter] COGS posting failed for fulfillment=#{fulfillment.id}: #{e.message}"
      end

      def parse_time(v)
        return nil if v.blank?
        v.is_a?(Time) || v.is_a?(ActiveSupport::TimeWithZone) ? v : Time.zone.parse(v.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
