class ProductionOrderSerializer
  def self.call(po)
    {
      id:                po.id,
      number:            po.number,
      parent_variant_id: po.parent_variant_id,
      parent_variant:    po.parent_variant && {
        id:            po.parent_variant.id,
        sku:           po.parent_variant.sku,
        title:         po.parent_variant.title,
        product_title: po.parent_variant.product&.title
      },
      warehouse_id:   po.warehouse_id,
      warehouse_name: po.warehouse&.name,
      quantity:       po.quantity,
      status:         po.status,
      production_mode: po.production_mode,
      unit_cost:      po.unit_cost,
      cost_currency:  po.cost_currency,
      computed_unit_cost: po.computed_unit_cost,
      total_cost:     po.total_cost,
      notes:          po.notes,
      started_at:     po.started_at,
      completed_at:   po.completed_at,
      cancelled_at:   po.cancelled_at,
      created_at:     po.created_at,
      updated_at:     po.updated_at,
      stages:         po.production_stages.map { |s| ProductionStageSerializer.call(s) }
    }
  end
end

class ProductionStageSerializer
  def self.call(stage)
    {
      id:            stage.id,
      production_order_id: stage.production_order_id,
      position:      stage.position,
      name:          stage.name,
      status:        stage.status,
      supplier_id:   stage.supplier_id,
      supplier_name: stage.supplier&.name,
      unit_cost:     stage.unit_cost,
      cost_currency: stage.cost_currency,
      started_at:    stage.started_at,
      completed_at:  stage.completed_at,
      notes:         stage.notes,
      created_at:    stage.created_at,
      updated_at:    stage.updated_at
    }
  end
end
