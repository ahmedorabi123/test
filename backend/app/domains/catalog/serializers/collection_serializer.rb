class CollectionSerializer
  def self.call(collection, include_products: false)
    {
      id:                    collection.id,
      shopify_collection_id: collection.shopify_collection_id,
      title:                 collection.title,
      handle:                collection.handle,
      body_html:             collection.body_html,
      image:                 collection.image,
      sort_order:            collection.sort_order,
      published_at:          collection.published_at,
      published_scope:       collection.published_scope,
      kind:                  collection.kind,
      rules:                 collection.rules || [],
      disjunctive:           collection.disjunctive,
      source:                collection.source,
      read_only_origin:      collection.shopify_origin?,
      products_count:        collection.products.size,
      shopify_updated_at:    collection.shopify_updated_at,
      created_at:            collection.created_at,
      updated_at:            collection.updated_at,
      products:              include_products ? collection.products.map { |p|
        { id: p.id, title: p.title, handle: p.handle, status: p.status,
          image: p.product_images.first&.src }
      } : nil
    }.compact
  end
end
