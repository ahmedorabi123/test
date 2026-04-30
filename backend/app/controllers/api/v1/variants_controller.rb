module Api
  module V1
    class VariantsController < ApplicationController
      # GET /api/v1/variants?search=&product_id=&page=&per_page=
      # Lightweight lookup endpoint (used by inventory create form).
      def index
        authorize Product, :index?
        scope = Variant.includes(:product)
        if params[:search].present?
          q = "%#{params[:search]}%"
          scope = scope.where(
            "variants.sku ILIKE :q OR variants.title ILIKE :q OR variants.barcode ILIKE :q",
            q: q
          ).or(
            Variant.joins(:product).where("products.title ILIKE :q OR products.handle ILIKE :q", q: q)
          )
        end
        scope = scope.where(product_id: params[:product_id]) if params[:product_id].present?

        page     = [params[:page].to_i, 1].max
        per_page = params[:per_page].to_i
        per_page = 25 if per_page <= 0
        per_page = 100 if per_page > 100

        records = scope.order("products.title ASC, variants.position ASC")
                       .offset((page - 1) * per_page).limit(per_page)

        render json: {
          data: records.map { |v|
            {
              id:            v.id,
              sku:           v.sku,
              title:         v.title,
              price:         v.price,
              product_id:    v.product_id,
              product_title: v.product&.title
            }
          },
          meta: { page: page, per_page: per_page, total: scope.count }
        }
      end
    end
  end
end
