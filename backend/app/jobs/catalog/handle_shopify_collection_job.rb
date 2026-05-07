module Catalog
  class HandleShopifyCollectionJob < ApplicationJob
    queue_as :default

    def perform(payload, kind:)
      Catalog::Shopify::CollectionUpserter.call(payload, kind: kind.to_sym)
    end
  end
end
