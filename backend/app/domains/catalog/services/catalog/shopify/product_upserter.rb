module Catalog
  module Shopify
    # Idempotently upserts a Shopify product+variant payload into the ERP catalog.
    # Accepts either a webhook payload (REST shape) or a GraphQL node (slightly
    # different shape) via `from:`.
    class ProductUpserter
      def self.call(payload, from: :webhook)
        new(payload, from: from).call
      end

      def initialize(payload, from:)
        @payload = payload.with_indifferent_access
        @from    = from.to_sym
      end

      def call
        ::Shopify::Origin.without_read_only do
          attrs = build_product_attrs
          product = Product.find_by(shopify_product_id: attrs[:shopify_product_id])
          # Fall back to matching by handle so we can claim products that were
          # seeded or imported without a shopify_product_id.
          product ||= Product.find_by(handle: attrs[:handle])
          product ||= Product.new
          product.assign_attributes(attrs)
          product.save!
          upsert_options(product)
          upsert_variants(product)
          upsert_images(product)
          product
        end
      end

      private

      attr_reader :payload, :from

      # The REST webhook and the GraphQL REST-shim payloads share almost the
      # same keys; tweak here if/when they diverge.
      def build_product_attrs
        {
          shopify_product_id:  payload[:id].to_i,
          shopify_updated_at:  parse_time(payload[:updated_at]),
          title:               payload[:title].presence || "Untitled",
          handle:              payload[:handle].presence || derive_handle(payload[:title]),
          status:              map_status(payload[:status]),
          vendor:              payload[:vendor],
          product_type:        payload[:product_type],
          description:         html_to_text(payload[:body_html]),
          tags:                normalize_tags(payload[:tags]),
          template_suffix:     payload[:template_suffix],
          published_at:        parse_time(payload[:published_at]),
          published_scope:     payload[:published_scope].presence || "web",
          seo_title:           payload.dig(:seo, :title) || payload[:seo_title],
          seo_description:     payload.dig(:seo, :description) || payload[:seo_description],
          source:              "shopify"
        }.compact
      end

      def upsert_options(product)
        opts = Array(payload[:options])
        return if opts.empty?

        keep_ids = []
        opts.each_with_index do |o, idx|
          oh = o.with_indifferent_access
          opt = product.product_options.find_or_initialize_by(name: oh[:name].to_s)
          opt.position = oh[:position].presence || (idx + 1)
          opt.save!
          keep_ids << opt.id

          values = Array(oh[:values])
          val_keep = []
          values.each_with_index do |v, vidx|
            # Use case-insensitive lookup to match the case-insensitive uniqueness
            # validation; avoids initializing a new record when "Red" vs "red" differ.
            row = opt.product_option_values
                     .where("lower(value) = lower(?)", v.to_s)
                     .first_or_initialize { |r| r.value = v.to_s }
            row.position = vidx + 1
            row.save!
            val_keep << row.id
          end
          opt.product_option_values.where.not(id: val_keep).destroy_all
        end
        product.product_options.where.not(id: keep_ids).destroy_all
      end

      def upsert_variants(product)
        incoming = Array(payload[:variants])
        keep_ids = []

        incoming.each_with_index do |v, idx|
          vh = v.with_indifferent_access
          variant = product.variants.find_or_initialize_by(shopify_variant_id: vh[:id].to_i)
          cost = vh[:cost]&.to_d || vh.dig(:inventory_item, :cost)&.to_d
          variant.assign_attributes(
            title:            vh[:title].presence || "Default Title",
            sku:              vh[:sku].presence,
            price:            (vh[:price] || 0).to_d,
            compare_at_price: vh[:compare_at_price]&.to_d,
            cost:             cost,
            cost_per_item:    cost,
            barcode:          vh[:barcode],
            position:         vh[:position].presence || (idx + 1),
            option1:          vh[:option1],
            option2:          vh[:option2],
            option3:          vh[:option3],
            weight:           vh[:weight]&.to_d,
            weight_unit:      vh[:weight_unit].presence || "kg",
            inventory_policy:    vh[:inventory_policy].presence    || "deny",
            inventory_management: vh[:inventory_management],
            requires_shipping: vh.key?(:requires_shipping) ? !!vh[:requires_shipping] : true,
            taxable:           vh.key?(:taxable) ? !!vh[:taxable] : true,
            fulfillment_service: vh[:fulfillment_service].presence || "manual",
            shopify_inventory_item_id: vh[:inventory_item_id]&.to_i
          )
          variant.save!
          Inventory::ProvisionStockItemsJob.perform_later(variant.id)
          keep_ids << variant.id
        end

        # Prune variants no longer present on the Shopify product (only when
        # processing a full-product payload, which is what webhooks send).
        if incoming.any?
          product.variants.where.not(id: keep_ids).find_each do |v|
            v.destroy
          rescue ActiveRecord::InvalidForeignKey
            # Variant is referenced by another record (e.g. production_orders); leave it.
          end
        end
      end

      def upsert_images(product)
        images = Array(payload[:images])
        return if images.empty?

        keep_ids = []
        images.each_with_index do |img, idx|
          ih = img.with_indifferent_access
          # Use global scope so we don't violate the unique index when an image
          # was previously associated with a different product record.
          rec = ProductImage.find_or_initialize_by(shopify_image_id: ih[:id].to_i)
          rec.product_id = product.id
          rec.assign_attributes(
            src:      ih[:src],
            alt:      ih[:alt],
            position: ih[:position].presence || (idx + 1),
            width:    ih[:width],
            height:   ih[:height]
          )
          rec.save!
          keep_ids << rec.id
        end
        product.product_images.where.not(shopify_image_id: nil).where.not(id: keep_ids).destroy_all
      end

      def normalize_tags(tags)
        case tags
        when Array  then tags.map(&:to_s).map(&:strip).reject(&:blank?)
        when String then tags.split(",").map(&:strip).reject(&:blank?)
        else []
        end
      end

      def map_status(s)
        return "active" if s.blank?
        s = s.to_s.downcase
        Product::STATUSES.include?(s) ? s : "active"
      end

      def derive_handle(title)
        title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      end

      def parse_time(v)
        return nil if v.blank?
        v.is_a?(Time) || v.is_a?(ActiveSupport::TimeWithZone) ? v : Time.zone.parse(v.to_s)
      rescue ArgumentError
        nil
      end

      def html_to_text(value)
        return nil if value.blank?

        text = ActionView::Base.full_sanitizer.sanitize(value.to_s)
        text.gsub(/\u00a0/, " ").gsub(/[ \t]+/, " ").gsub(/\n{3,}/, "\n\n").strip
      end
    end
  end
end
