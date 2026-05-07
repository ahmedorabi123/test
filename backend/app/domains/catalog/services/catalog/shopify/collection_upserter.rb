module Catalog
  module Shopify
    # Idempotently upserts a Shopify collection (custom or smart) into the
    # ERP catalog. Smart-collection rules are stored as JSON but never
    # evaluated locally (read-only in the UI).
    class CollectionUpserter
      def self.call(payload, kind:)
        new(payload, kind: kind).call
      end

      def initialize(payload, kind:)
        @payload = payload.with_indifferent_access
        @kind    = kind.to_s
      end

      def call
        attrs = build_attrs
        collection = Collection.find_by(shopify_collection_id: attrs[:shopify_collection_id])
        collection ||= Collection.find_by(handle: attrs[:handle])
        collection ||= Collection.new
        collection.assign_attributes(attrs)
        collection.save!
        collection
      end

      private

      def build_attrs
        rules = Array(@payload[:rules]).map do |r|
          { "column"    => r[:column].to_s,
            "relation"  => r[:relation].to_s,
            "condition" => r[:condition].to_s }
        end

        {
          shopify_collection_id: @payload[:id].to_i,
          shopify_updated_at:    parse_time(@payload[:updated_at]),
          title:                 @payload[:title].presence || "Untitled Collection",
          handle:                @payload[:handle].presence,
          body_html:             @payload[:body_html],
          image:                 @payload.dig(:image, :src),
          sort_order:            @payload[:sort_order].presence || "manual",
          published_at:          parse_time(@payload[:published_at]),
          published_scope:       @payload[:published_scope].presence || "web",
          kind:                  @kind,
          rules:                 rules,
          disjunctive:           @payload[:disjunctive] == true || @payload[:disjunctive] == "true",
          source:                "shopify"
        }.compact
      end

      def parse_time(val)
        return nil if val.blank?
        Time.zone.parse(val.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
