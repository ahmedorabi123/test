module Catalog
  module MetafieldRegistry
    CATEGORY_NAMESPACE = "category".freeze

    DEFINITIONS = [
      { namespace: CATEGORY_NAMESPACE, key: "color", label: "Color", type: "single_line_text_field" },
      { namespace: CATEGORY_NAMESPACE, key: "size", label: "Size", type: "single_line_text_field" },
      { namespace: CATEGORY_NAMESPACE, key: "fabric", label: "Fabric", type: "single_line_text_field" },
      { namespace: CATEGORY_NAMESPACE, key: "age_group", label: "Age group", type: "single_line_text_field" },
      { namespace: CATEGORY_NAMESPACE, key: "neckline", label: "Neckline", type: "single_line_text_field" },
      { namespace: CATEGORY_NAMESPACE, key: "sleeve_length", label: "Sleeve length", type: "single_line_text_field" },
      { namespace: CATEGORY_NAMESPACE, key: "target_gender", label: "Target gender", type: "single_line_text_field" },
      { namespace: CATEGORY_NAMESPACE, key: "material", label: "Material", type: "single_line_text_field" }
    ].freeze

    def self.category_keys = DEFINITIONS.map { |definition| definition[:key] }

    def self.category_values(product)
      rows = Array(product.metafields).map { |row| row.with_indifferent_access }
      DEFINITIONS.to_h do |definition|
        hit = rows.find do |row|
          row[:namespace].to_s == definition[:namespace] && row[:key].to_s == definition[:key]
        end
        [definition[:key], hit&.[](:value)]
      end
    end
  end
end