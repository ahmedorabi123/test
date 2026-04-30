module Api
  module V1
    # Manage BOM components for a parent variant.
    # Endpoints:
    #   GET    /api/v1/variants/:variant_id/bom_items
    #   POST   /api/v1/variants/:variant_id/bom_items
    #   PATCH  /api/v1/variants/:variant_id/bom_items/:id
    #   DELETE /api/v1/variants/:variant_id/bom_items/:id
    class BomItemsController < ApplicationController
      before_action :set_parent
      before_action :set_item, only: %i[update destroy]

      def index
        authorize Product, :show?
        items = BomItem.where(parent_variant_id: @parent.id).includes(component_variant: :product)
        render json: {
          data: items.map { |bi| serialize(bi) }
        }
      end

      def create
        authorize Product, :update?
        bi = BomItem.new(permitted_params.merge(parent_variant_id: @parent.id))
        if bi.save
          render json: { data: serialize(bi) }, status: :created
        else
          render json: { error: { type: "invalid", detail: bi.errors.full_messages.join(", ") } }, status: :unprocessable_entity
        end
      end

      def update
        authorize Product, :update?
        if @item.update(permitted_params.except(:component_variant_id))
          render json: { data: serialize(@item) }
        else
          render json: { error: { type: "invalid", detail: @item.errors.full_messages.join(", ") } }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize Product, :update?
        @item.destroy!
        head :no_content
      end

      private

      def set_parent
        @parent = Variant.find(params[:variant_id])
      end

      def set_item
        @item = BomItem.find(params[:id])
      end

      def permitted_params
        params.require(:bom_item).permit(:component_variant_id, :quantity, :waste_factor)
      end

      def serialize(bi)
        cv = bi.component_variant
        {
          id:                   bi.id,
          parent_variant_id:    bi.parent_variant_id,
          component_variant_id: bi.component_variant_id,
          component: cv && {
            id:            cv.id,
            sku:           cv.sku,
            title:         cv.title,
            product_title: cv.product&.title
          },
          quantity:     bi.quantity,
          waste_factor: bi.waste_factor
        }
      end
    end
  end
end
