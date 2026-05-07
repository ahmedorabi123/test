module Catalog
  class AssignCollectionsToProduct
    class InvalidCollection < StandardError; end

    def self.call(product, collection_ids)
      new(product, collection_ids).call
    end

    def initialize(product, collection_ids)
      @product = product
      @collection_ids = Array(collection_ids).reject(&:blank?).uniq
    end

    def call
      collections = Collection.where(id: @collection_ids)
      missing = @collection_ids.map(&:to_s) - collections.map { |collection| collection.id.to_s }
      raise InvalidCollection, "Collection not found: #{missing.first}" if missing.any?

      smart = collections.find(&:smart?)
      raise InvalidCollection, "Smart collections are read-only and cannot be assigned manually" if smart

      @product.collections = collections
      @product
    end
  end
end