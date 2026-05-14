module Api
  module V1
    class VariantsController < ApplicationController
      # GET /api/v1/variants?search=&product_id=&warehouse_id=&min_available=&in_stock=true&include=stock_items_summary&page=&per_page=
      # Lightweight lookup endpoint (used by inventory + manual-order forms).
      # When warehouse_id + (min_available > 0 OR in_stock=true) are given,
      # results are filtered to variants with sufficient available stock at
      # that warehouse and sorted by available DESC so the most in-stock
      # variants appear first.
      def index
        authorize Product, :index?
        scope = Variant.includes(:product)
        scope = scope.where(id: Array(params[:ids]).flat_map { |value| value.to_s.split(",") }.reject(&:blank?)) if params[:ids].present?
        if params[:search].present?
          q = "%#{params[:search]}%"
          scope = scope.left_outer_joins(:product).where(
            "variants.sku ILIKE :q OR variants.title ILIKE :q OR variants.barcode ILIKE :q OR products.title ILIKE :q OR products.handle ILIKE :q",
            q: q
          )
        end
        scope = scope.where(product_id: params[:product_id]) if params[:product_id].present?

        warehouse_id  = params[:warehouse_id].presence
        min_available = [params[:min_available].to_i, params[:in_stock].to_s == "true" ? 1 : 0].max

        if warehouse_id
          warehouse = Warehouse.find_by(id: warehouse_id)
          if warehouse.nil?
            return render_error(404, "not_found", "Warehouse not found")
          end
          if warehouse.shopify_origin?
            return render_error(
              422,
              "unprocessable_entity",
              "Cannot list variants for a Shopify-managed warehouse from this endpoint. Manual orders must target a non-Shopify warehouse."
            )
          end
        end

        if warehouse_id && min_available > 0
          # Inner-join to stock_items so we both filter and can sort by available.
          # Clamp to 0 to match StockItem#available semantics (negative deltas are
          # not "available" — a variant over-reserved should NOT appear in the
          # in-stock list).
          available_expr = "GREATEST(stock_items.quantity_on_hand - stock_items.quantity_reserved - stock_items.quantity_unavailable, 0)"
          scope = scope.joins(:stock_items)
                       .where(stock_items: { warehouse_id: warehouse_id })
                       .where("#{available_expr} >= ?", min_available)
                       .order(Arel.sql("#{available_expr} DESC, products.title ASC, variants.position ASC"))
        else
          scope = scope.order("products.title ASC, variants.position ASC")
        end

        page     = [params[:page].to_i, 1].max
        per_page = params[:per_page].to_i
        per_page = 25 if per_page <= 0
        per_page = 100 if per_page > 100

        records = scope.offset((page - 1) * per_page).limit(per_page)

        stock_items_by_variant = stock_items_summary(records)

        render json: {
          data: records.map { |v| variant_payload(v, stock_items_by_variant[v.id] || []) },
          meta: { page: page, per_page: per_page, total: scope.count }
        }
      end

      private

      def stock_items_summary(records)
        return {} unless params[:include].to_s.split(",").include?("stock_items_summary")

        scope = StockItem.where(variant_id: records.map(&:id)).includes(:warehouse)
        scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?
        scope.group_by(&:variant_id)
      end

      def variant_payload(variant, stock_items)
        {
          id: variant.id,
          sku: variant.sku,
          title: variant.title,
          price: variant.price,
          shopify_variant_id: variant.shopify_variant_id,
          read_only_origin: variant.shopify_origin?,
          product_id: variant.product_id,
          product_title: variant.product&.title,
          product_source: variant.product&.source,
          product_shopify_product_id: variant.product&.shopify_product_id,
          product_read_only_origin: variant.product&.shopify_origin?,
          stock_items: stock_items.map do |stock_item|
            {
              id: stock_item.id,
              warehouse_id: stock_item.warehouse_id,
              warehouse_name: stock_item.warehouse&.name,
              quantity_on_hand: stock_item.quantity_on_hand,
              quantity_reserved: stock_item.quantity_reserved,
              quantity_unavailable: stock_item.quantity_unavailable,
              available: stock_item.available,
              low_stock_threshold: stock_item.low_stock_threshold
            }
          end
        }
      end
    end
  end
end
