module Api
  module V1
    class ProductsController < ApplicationController
      include Sortable
      include Exportable
      include Importable

      sortable_by "title", "handle", "vendor", "status", "product_type",
                  "updated_at", "created_at", "inventory_total", "source",
                  default: { updated_at: :desc }

      INVENTORY_SORT_SQL = <<~SQL.squish.freeze
        LEFT JOIN (
          SELECT variants.product_id,
                 COALESCE(SUM(stock_items.quantity_on_hand), 0) AS inv_total
          FROM variants
          LEFT JOIN stock_items ON stock_items.variant_id = variants.id
          GROUP BY variants.product_id
        ) inv_rollup ON inv_rollup.product_id = products.id
      SQL

      before_action :set_product, only: %i[show update destroy]
      before_action :ensure_product_mutable, only: %i[update destroy]

      # GET /api/v1/products?search=&status=&page=&per_page=&sort=&dir=
      def index
        authorize Product
        scope = filtered_scope

        page     = params[:page].to_i
        page     = 1 if page < 1
        per_page = params[:per_page].to_i
        per_page = 25 if per_page <= 0
        per_page = 200 if per_page > 200

        records  = apply_sort(scope).offset((page - 1) * per_page).limit(per_page)
        total    = scope.count

        render json: {
          data: records.map { |p| ProductSerializer.call(p, include_variants: false) },
          meta: { page: page, per_page: per_page, total: total }
        }
      end

      # Override Sortable#apply_sort to handle the virtual inventory_total column.
      def apply_sort(scope)
        if params[:sort].to_s == "inventory_total"
          dir = params[:dir].to_s.downcase == "desc" ? "DESC" : "ASC"
          scope
            .joins(INVENTORY_SORT_SQL)
            .order(Arel.sql("inv_rollup.inv_total #{dir} NULLS LAST, products.id #{dir}"))
        else
          super
        end
      end

      def show
        authorize @product
        render json: { data: ProductSerializer.call(@product) }
      end

      def create
        authorize Product
        attrs = product_params.to_h.with_indifferent_access
        collection_ids = attrs.delete(:collection_ids)
        product = nil

        Product.transaction do
          product = Product.new(attrs)
          product.save!
          Catalog::AssignCollectionsToProduct.call(product, collection_ids) if collection_ids
          Inventory::ProvisionStockItems.call(product: product) if provision_stock_items?(attrs)
        end

        render json: { data: ProductSerializer.call(product) }, status: :created
      rescue Catalog::AssignCollectionsToProduct::InvalidCollection => e
        render_error(422, "unprocessable_entity", e.message)
      end

      def update
        authorize @product
        attrs = product_params.to_h.with_indifferent_access
        collection_ids = attrs.delete(:collection_ids)

        Product.transaction do
          @product.update!(attrs)
          Catalog::AssignCollectionsToProduct.call(@product, collection_ids) if collection_ids
        end

        render json: { data: ProductSerializer.call(@product) }
      rescue Catalog::AssignCollectionsToProduct::InvalidCollection => e
        render_error(422, "unprocessable_entity", e.message)
      end

      def destroy
        authorize @product
        if product_has_references?(@product)
          @product.update!(status: "archived")
          render json: {
            data: ProductSerializer.call(@product, include_variants: false),
            meta: { archived: true, reason: "Product has order history and was archived instead of deleted." }
          }
        else
          @product.destroy!
          head :no_content
        end
      end

      # POST /api/v1/products/bulk
      def bulk
        authorize Product
        ids = Array(params[:ids])
        action_type = params[:action_type].to_s
        scope = Product.where(id: ids)
        count = 0

        case action_type
        when "archive"
          return unless ensure_no_shopify_origin!(scope)
          scope.find_each { |p| p.update!(status: "archived"); count += 1 }
        when "activate"
          return unless ensure_no_shopify_origin!(scope)
          scope.find_each { |p| p.update!(status: "active"); count += 1 }
        when "delete"
          return unless ensure_no_shopify_origin!(scope)
          scope.find_each { |p| p.destroy!; count += 1 }
        else
          return render_error(400, "bad_request", "Unsupported action: #{action_type}")
        end

        render json: { data: { action: action_type, affected: count } }
      end

      private

      def filtered_scope
        scope = policy_scope(Product).includes(:collections, :product_options, :product_images, variants: :stock_items)
        scope = scope.where("products.title ILIKE :q OR products.handle ILIKE :q", q: "%#{params[:search]}%") if params[:search].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.from_shopify if params[:from_shopify].to_s == "true"
        if params[:collection_id].present?
          scope = scope.joins(:collection_products)
                       .where(collection_products: { collection_id: params[:collection_id] })
        end
        scope
      end

      def product_has_references?(product)
        variant_ids = product.variant_ids
        return false if variant_ids.empty?
        OrderLineItem.where(variant_id: variant_ids).exists? ||
          PurchaseOrderLineItem.where(variant_id: variant_ids).exists?
      end

      def set_product
        @product = Product
          .includes(
            collections: [],
            product_options: :product_option_values,
            product_images: [],
            variants: { stock_items: :warehouse }
          )
          .find(params[:id])
      end

      def ensure_product_mutable
        ensure_not_shopify_origin!(@product)
      end

      def product_params
        params.require(:product).permit(
          :title, :handle, :status, :vendor, :product_type, :description,
          :seo_title, :seo_description, :template_suffix,
          :published_at, :published_scope, :gift_card,
          tags: [],
          collection_ids: [],
          metafields: [ :namespace, :key, :type, :value ],
          variants_attributes: [
            :id, :sku, :title, :price, :compare_at_price, :cost, :cost_per_item,
            :barcode, :position, :_destroy,
            :option1, :option2, :option3,
            :weight, :weight_unit,
            :inventory_policy, :inventory_management,
            :requires_shipping, :taxable, :fulfillment_service,
            :hs_code, :country_of_origin,
            stock_items_attributes: [ :id, :warehouse_id, :quantity_on_hand, :low_stock_threshold ]
          ],
          product_options_attributes: [
            :id, :name, :position, :_destroy,
            product_option_values_attributes: [ :id, :value, :position, :_destroy ]
          ],
          product_images_attributes: [
            :id, :src, :alt, :position, :width, :height, :variant_id, :_destroy
          ]
        )
      end

      def nested_stock_items?(attrs)
        Array(attrs[:variants_attributes]).any? { |variant_attrs| Array(variant_attrs[:stock_items_attributes]).any? }
      end

      def provision_stock_items?(attrs)
        return false if nested_stock_items?(attrs)

        ActiveModel::Type::Boolean.new.cast(params.fetch(:provision_stock, true))
      end

      def export_scope
        authorize Product
        apply_sort(filtered_scope)
      end

      def export_columns
        {
          "Handle"       => :handle,
          "Title"        => :title,
          "Status"       => :status,
          "Vendor"       => :vendor,
          "Product Type" => :product_type,
          "Tags"         => ->(p) { Array(p.tags).join(", ") },
          "Description"  => :description,
          "SEO Title"    => :seo_title,
          "SEO Description" => :seo_description,
          "Published At" => :published_at,
          "Variants"     => ->(p) { p.variants.size },
          "Shopify Id"   => :shopify_product_id,
          "Updated At"   => :updated_at
        }
      end

      def importer_class
        authorize Product, :create?
        Imports::ProductsImporter
      end
    end
  end
end
