module Api
  module V1
    class CollectionsController < ApplicationController
      include Sortable

      sortable_by "title", "kind", "products_count", "published_at", "created_at", "source",
                  default: { created_at: :desc }

      PRODUCTS_COUNT_SORT_SQL = <<~SQL.squish.freeze
        LEFT JOIN (
          SELECT collection_products.collection_id,
                 COUNT(collection_products.product_id) AS products_count
          FROM collection_products
          GROUP BY collection_products.collection_id
        ) collection_rollup ON collection_rollup.collection_id = collections.id
      SQL

      before_action :set_collection, only: %i[show update destroy add_product remove_product]
      before_action :ensure_collection_mutable, only: %i[update destroy add_product remove_product]

      # GET /api/v1/collections
      def index
        authorize Collection
        scope = filtered_scope

        page     = [params[:page].to_i, 1].max
        per_page = params[:per_page].to_i
        per_page = 25  if per_page <= 0
        per_page = 200 if per_page > 200

        records = apply_sort(scope).offset((page - 1) * per_page).limit(per_page)
        total   = scope.count
        kind_counts = filtered_scope(ignore_kind: true).group(:kind).count

        render json: {
          data: records.map { |c| CollectionSerializer.call(c) },
          meta: { page: page, per_page: per_page, total: total, kind_counts: kind_counts }
        }
      end

      def apply_sort(scope)
        if params[:sort].to_s == "products_count"
          dir = params[:dir].to_s.downcase == "desc" ? "DESC" : "ASC"
          scope
            .joins(PRODUCTS_COUNT_SORT_SQL)
            .order(Arel.sql("COALESCE(collection_rollup.products_count, 0) #{dir}, collections.id #{dir}"))
        else
          super
        end
      end

      # GET /api/v1/collections/:id
      def show
        authorize @collection
        render json: { data: CollectionSerializer.call(@collection, include_products: true) }
      end

      # POST /api/v1/collections
      def create
        authorize Collection
        if params.dig(:collection, :kind) == "smart"
          return render_error(422, "unprocessable_entity",
                              "Smart collections are managed by Shopify and cannot be created here.")
        end

        collection = Collection.new(collection_params.merge(kind: "custom"))
        if collection.save
          render json: { data: CollectionSerializer.call(collection) }, status: :created
        else
          render_error(422, "unprocessable_entity", collection.errors.full_messages.join(", "))
        end
      end

      # PATCH /api/v1/collections/:id
      def update
        authorize @collection
        if @collection.smart? && collection_params.key?(:rules)
          return render_error(403, "forbidden", "Smart collection rules are read-only in ERP.")
        end

        safe_params = collection_params.except(:kind)
        if @collection.update(safe_params)
          render json: { data: CollectionSerializer.call(@collection) }
        else
          render_error(422, "unprocessable_entity", @collection.errors.full_messages.join(", "))
        end
      end

      # DELETE /api/v1/collections/:id
      def destroy
        authorize @collection
        if @collection.smart?
          return render_error(403, "forbidden",
                              "Smart collections are managed by Shopify and cannot be deleted here.")
        end

        @collection.destroy!
        head :no_content
      end

      # POST /api/v1/collections/:id/products  { product_id:, position: }
      def add_product
        authorize @collection, :update?
        product = Product.find(params[:product_id])
        Catalog::AssignCollectionsToProduct.validate!(product, [@collection])
        cp = @collection.collection_products.find_or_create_by!(product: product)
        cp.update!(position: params[:position].to_i) if params[:position].present?
        render json: { data: CollectionSerializer.call(@collection, include_products: true) }
      rescue Catalog::AssignCollectionsToProduct::InvalidCollection => e
        render_error(422, "invalid_collection", e.message)
      end

      # DELETE /api/v1/collections/:id/products/:product_id
      def remove_product
        authorize @collection, :update?
        @collection.collection_products.where(product_id: params[:product_id]).destroy_all
        render json: { data: CollectionSerializer.call(@collection, include_products: true) }
      end

      private

      def set_collection
        @collection = Collection.find(params[:id])
      end

      def ensure_collection_mutable
        ensure_not_shopify_origin!(@collection)
      end

      def filtered_scope(ignore_kind: false)
        scope = policy_scope(Collection).includes(:collection_products)
        scope = scope.where("title ILIKE :q OR handle ILIKE :q", q: "%#{params[:search]}%") if params[:search].present?
        scope = scope.where(kind: params[:kind]) if params[:kind].present? && !ignore_kind
        scope
      end

      def collection_params
        params.require(:collection).permit(
          :title, :handle, :body_html, :image, :sort_order,
          :published_at, :published_scope, :kind, :disjunctive,
          rules: [:column, :relation, :condition]
        )
      end
    end
  end
end
