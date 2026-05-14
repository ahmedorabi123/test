module Catalog
  class AssignCollectionsToProduct
    class InvalidCollection < StandardError; end

    def self.call(product, collection_ids)
      new(product, collection_ids).call
    end

    def self.validate!(product, collections)
      validate_product!(product)
      validate_collections!(Array(collections))
    end

    def initialize(product, collection_ids)
      @product = product
      @collection_ids = Array(collection_ids).reject(&:blank?).uniq
    end

    def call
      collections = Collection.where(id: @collection_ids)
      missing = @collection_ids.map(&:to_s) - collections.map { |collection| collection.id.to_s }
      raise InvalidCollection, "Collection not found: #{missing.first}" if missing.any?

      self.class.validate!(@product, collections)

      @product.collections = collections
      @product
    end

    def self.validate_product!(product)
      return unless product.respond_to?(:shopify_origin?) && product.shopify_origin?

      raise InvalidCollection, "Shopify-managed products cannot be assigned to collections manually"
    end
    private_class_method :validate_product!

    def self.validate_collections!(collections)
      smart = collections.find(&:smart?)
      raise InvalidCollection, "Smart collections are read-only and cannot be assigned manually" if smart

      shopify = collections.find { |collection| collection.respond_to?(:shopify_origin?) && collection.shopify_origin? }
      return unless shopify

      raise InvalidCollection, "Shopify-managed collections are read-only and cannot be assigned manually"
    end
    private_class_method :validate_collections!
  end
end