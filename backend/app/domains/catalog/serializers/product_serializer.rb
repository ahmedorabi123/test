# Serializes a Product (optionally with variants). Plain-Ruby to avoid adding
# JSON:API gem weight for the MVP.
class ProductSerializer
  def self.call(product, include_variants: true)
    # Stock rollup — computed from preloaded associations (no N+1 when
    # filtered_scope uses includes(variants: :stock_items)).
    all_stock_items = product.variants.flat_map(&:stock_items)
    inventory_total = all_stock_items.sum(&:quantity_on_hand)
    variants_in_stock = product.variants.count { |v| v.stock_items.any? { |s| s.quantity_on_hand > 0 } }
    collections = product.collections.map { |c| { id: c.id, title: c.title, handle: c.handle } }

    {
      id:                      product.id,
      title:                   product.title,
      handle:                  product.handle,
      status:                  product.status,
      vendor:                  product.vendor,
      product_type:            product.product_type,
      description:             product.description,
      tags:                    product.tags || [],
      metafields:              product.metafields || [],
      category_metafields:     Catalog::MetafieldRegistry.category_values(product),
      seo_title:               product.seo_title,
      seo_description:         product.seo_description,
      template_suffix:         product.template_suffix,
      published_at:            product.published_at,
      published_scope:         product.published_scope,
      gift_card:               product.gift_card,
      shopify_product_id:      product.shopify_product_id,
      shopify_updated_at:      product.shopify_updated_at,
      source:                  product.source,
      read_only_origin:        product.shopify_origin?,
      collections:             collections,
      primary_category:        collections.first&.fetch(:title, nil) || product.product_type,
      created_at:              product.created_at,
      updated_at:              product.updated_at,
      variants_count:          product.variants.size,
      inventory_total:         inventory_total,
      variants_in_stock_count: variants_in_stock,
      options:  product.product_options.map { |o| ProductOptionSerializer.call(o) },
      images:   product.product_images.map  { |i| ProductImageSerializer.call(i) },
      uploaded_images: uploaded_images_payload(product),
      variants: include_variants ? product.variants.map { |v| VariantSerializer.call(v) } : nil
    }.compact
  end

  def self.uploaded_images_payload(product)
    return [] unless product.respond_to?(:uploaded_images) && product.uploaded_images.attached?
    product.uploaded_images_attachments.map do |attachment|
      {
        id:           attachment.id,
        filename:     attachment.filename.to_s,
        content_type: attachment.content_type,
        byte_size:    attachment.byte_size,
        url:          Rails.application.routes.url_helpers.rails_blob_path(attachment, only_path: true)
      }
    end
  rescue StandardError
    []
  end
end

class VariantSerializer
  def self.call(variant)
    {
      id:                variant.id,
      product_id:        variant.product_id,
      sku:               variant.sku,
      title:             variant.title,
      price:             variant.price,
      compare_at_price:  variant.compare_at_price,
      cost:              variant.cost,
      last_purchase_cost: variant.last_purchase_cost,
      cost_per_item:     variant.cost_per_item,
      barcode:           variant.barcode,
      position:          variant.position,
      option1:           variant.option1,
      option2:           variant.option2,
      option3:           variant.option3,
      weight:            variant.weight,
      weight_unit:       variant.weight_unit,
      inventory_policy:  variant.inventory_policy,
      inventory_management: variant.inventory_management,
      requires_shipping: variant.requires_shipping,
      taxable:           variant.taxable,
      fulfillment_service: variant.fulfillment_service,
      hs_code:            variant.hs_code,
      country_of_origin:  variant.country_of_origin,
      shopify_variant_id:         variant.shopify_variant_id,
      shopify_inventory_item_id:  variant.shopify_inventory_item_id,
      read_only_origin:           variant.shopify_origin?,
      stock_items: variant.stock_items.map { |si|
        {
          id:               si.id,
          warehouse_id:     si.warehouse_id,
          warehouse_name:   si.warehouse&.name || "Warehouse #{si.warehouse_id}",
          warehouse_code:   si.warehouse&.code,
          quantity_on_hand: si.quantity_on_hand,
          quantity_reserved: si.quantity_reserved,
          quantity_unavailable: si.quantity_unavailable,
          available: si.available,
          low_stock_threshold: si.low_stock_threshold,
          read_only_origin: si.shopify_origin?
        }
      }
    }
  end
end

class ProductOptionSerializer
  def self.call(option)
    {
      id:       option.id,
      name:     option.name,
      position: option.position,
      values:   option.product_option_values.map { |v| { id: v.id, value: v.value, position: v.position } }
    }
  end
end

class ProductImageSerializer
  def self.call(image)
    {
      id:         image.id,
      src:        image.src,
      alt:        image.alt,
      position:   image.position,
      width:      image.width,
      height:     image.height,
      variant_id: image.variant_id,
      shopify_image_id: image.shopify_image_id
    }
  end
end
