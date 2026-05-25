class CollectionSerializer
  def self.call(collection, include_products: false)
    {
      id:                    collection.id,
      shopify_collection_id: collection.shopify_collection_id,
      title:                 collection.title,
      handle:                collection.handle,
      body_html:             collection.body_html,
      image:                 uploaded_image_url(collection) || collection.image,
      uploaded_image:        uploaded_image_payload(collection),
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

  def self.uploaded_image_url(collection)
    return nil unless collection.uploaded_image.attached?

    Rails.application.routes.url_helpers.rails_blob_path(collection.uploaded_image, only_path: true)
  rescue StandardError
    nil
  end

  def self.uploaded_image_payload(collection)
    return nil unless collection.uploaded_image.attached?

    attachment = collection.uploaded_image.attachment
    {
      id: attachment.id,
      filename: attachment.filename.to_s,
      content_type: attachment.content_type,
      byte_size: attachment.byte_size,
      url: Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
    }
  rescue StandardError
    nil
  end
end
