# Shopify-compatible product CSV import.
#
# Expected headers (subset of Shopify's product export CSV):
#   Handle, Title, Body (HTML), Vendor, Product Type, Tags, Status,
#   Variant SKU, Variant Price, Variant Compare At Price, Variant Barcode,
#   Option1 Name, Option1 Value
#
# Rows that share the same Handle are grouped into one product with
# multiple variants (Shopify's own export shape).
module Imports
  class ProductsImporter < Base
    HEADERS = %w[Handle Title].freeze

    STATUS_MAP = {
      "active"    => "active",
      "draft"     => "draft",
      "archived"  => "archived"
    }.freeze

    def validate_row(row, row_num)
      errors = []
      warnings = []

      handle = row["Handle"].to_s.strip
      if handle.blank?
        errors << { row: row_num, message: "Handle is required" }
      end

      title = row["Title"].to_s.strip
      is_variant_continuation = title.blank? && handle.present?

      status = row["Status"].to_s.strip.downcase
      if status.present? && !STATUS_MAP.key?(status)
        warnings << { row: row_num, message: "Unknown status '#{status}', defaulting to draft" }
      end

      price = row["Variant Price"].to_s.strip
      if price.present? && Float(price, exception: false).nil?
        errors << { row: row_num, message: "Variant Price '#{price}' is not numeric" }
      end

      if row_num > 1 && title.blank? && handle.blank?
        warnings << { row: row_num, message: "Skipped empty row" }
      end

      _ = is_variant_continuation
      [errors, warnings]
    end

    def persist_row(row)
      handle = row["Handle"].to_s.strip.downcase
      return nil if handle.blank?

      product = Product.find_or_initialize_by(handle: handle)
      was_new = product.new_record?

      title  = row["Title"].to_s.strip.presence
      status = STATUS_MAP[row["Status"].to_s.strip.downcase] || "draft"

      # First row for a handle carries product-level fields. Subsequent rows
      # with the same handle are variants-only (Shopify's convention).
      if title.present? || was_new
        tags = row["Tags"].to_s.split(",").map(&:strip).reject(&:blank?)
        product.assign_attributes(
          title:           title || product.title || handle.titleize,
          status:          status,
          vendor:          row["Vendor"].to_s.strip.presence,
          product_type:    row["Product Type"].to_s.strip.presence,
          description:     row["Body (HTML)"].to_s.presence,
          tags:            tags,
          seo_title:       row["SEO Title"].to_s.strip.presence,
          seo_description: row["SEO Description"].to_s.presence,
          gift_card:       row["Gift Card"].to_s.strip.casecmp("true").zero?,
          published_scope: row["Published Scope"].to_s.strip.presence || "web"
        )
      end
      product.save!

      # Upsert option definitions if present (Shopify's "Option1 Name" etc).
      %w[1 2 3].each do |n|
        opt_name = row["Option#{n} Name"].to_s.strip
        next if opt_name.blank?
        opt = product.product_options.find_or_initialize_by(name: opt_name)
        opt.position = n.to_i
        opt.save!
        opt_value = row["Option#{n} Value"].to_s.strip
        if opt_value.present?
          val = opt.product_option_values.find_or_initialize_by(value: opt_value)
          val.position = (opt.product_option_values.size + 1) if val.new_record?
          val.save!
        end
      end

      # Image row (Shopify's CSV uses "Image Src", "Image Position", "Image Alt Text").
      img_src = row["Image Src"].to_s.strip
      if img_src.present?
        img = product.product_images.find_or_initialize_by(src: img_src)
        img.position = row["Image Position"].to_s.to_i.nonzero? || (product.product_images.size + 1)
        img.alt      = row["Image Alt Text"].to_s.strip.presence
        img.save!
      end

      # Attach / update a variant if SKU or price present on this row.
      sku   = row["Variant SKU"].to_s.strip.presence
      price = row["Variant Price"].to_s.strip.presence
      if sku.present? || price.present?
        variant_title = [row["Option1 Value"], row["Option2 Value"], row["Option3 Value"]]
                          .compact.map(&:to_s).map(&:strip).reject(&:blank?).join(" / ").presence || "Default"
        variant = product.variants.find_by(sku: sku) if sku.present?
        variant ||= product.variants.find_or_initialize_by(title: variant_title)
        variant.assign_attributes(
          sku:              sku,
          title:            variant_title,
          price:            price || variant.price || 0,
          compare_at_price: row["Variant Compare At Price"].to_s.strip.presence,
          barcode:          row["Variant Barcode"].to_s.strip.presence,
          position:         variant.position.presence || (product.variants.size + 1),
          option1:          row["Option1 Value"].to_s.strip.presence,
          option2:          row["Option2 Value"].to_s.strip.presence,
          option3:          row["Option3 Value"].to_s.strip.presence,
          weight:           row["Variant Grams"].to_s.to_d.nonzero? ? (row["Variant Grams"].to_d / 1000.0) : nil,
          weight_unit:      row["Variant Weight Unit"].to_s.strip.presence || "kg",
          inventory_policy: row["Variant Inventory Policy"].to_s.strip.presence    || "deny",
          inventory_management: row["Variant Inventory Tracker"].to_s.strip.presence,
          requires_shipping: row["Variant Requires Shipping"].to_s.strip.casecmp("false").zero? ? false : true,
          taxable:           row["Variant Taxable"].to_s.strip.casecmp("false").zero? ? false : true,
          fulfillment_service: row["Variant Fulfillment Service"].to_s.strip.presence || "manual",
          cost_per_item:    row["Cost per item"].to_s.strip.presence || row["Variant Cost"].to_s.strip.presence,
          hs_code:          row["Variant HS Code"].to_s.strip.presence || row["HS Code"].to_s.strip.presence,
          country_of_origin: row["Variant Country of Origin"].to_s.strip.presence || row["Country of Origin"].to_s.strip.presence
        )
        variant.save!
      end

      was_new ? :created : :updated
    end
  end
end
