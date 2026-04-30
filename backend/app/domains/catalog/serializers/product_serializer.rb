# Serializes a Product (optionally with variants). Plain-Ruby to avoid adding
# JSON:API gem weight for the MVP.
class ProductSerializer
  def self.call(product, include_variants: true)
    {
      id:                  product.id,
      title:               product.title,
      handle:              product.handle,
      status:              product.status,
      vendor:              product.vendor,
      product_type:        product.product_type,
      description:         product.description,
      tags:                product.tags || [],
      seo_title:           product.seo_title,
      seo_description:     product.seo_description,
      template_suffix:     product.template_suffix,
      published_at:        product.published_at,
      published_scope:     product.published_scope,
      gift_card:           product.gift_card,
      shopify_product_id:  product.shopify_product_id,
      shopify_updated_at:  product.shopify_updated_at,
      created_at:          product.created_at,
      updated_at:          product.updated_at,
      variants_count:      include_variants ? nil : product.variants.size,
      options:  product.product_options.map { |o| ProductOptionSerializer.call(o) },
      images:   product.product_images.map  { |i| ProductImageSerializer.call(i) },
      variants: include_variants ? product.variants.map { |v| VariantSerializer.call(v) } : nil
    }.compact
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
      shopify_inventory_item_id:  variant.shopify_inventory_item_id
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
