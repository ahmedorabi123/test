class BomItem < ApplicationRecord
  self.table_name = "bom_items"

  belongs_to :parent_variant,
             class_name: "Variant",
             foreign_key: :parent_variant_id
  belongs_to :component_variant,
             class_name: "Variant",
             foreign_key: :component_variant_id

  validates :quantity,     numericality: { greater_than: 0 }
  validates :waste_factor, numericality: { greater_than_or_equal_to: 0, less_than: 1 }
  validate  :no_self_reference

  private

  def no_self_reference
    return unless parent_variant_id.present? && parent_variant_id == component_variant_id
    errors.add(:component_variant_id, "cannot equal parent variant")
  end
end
