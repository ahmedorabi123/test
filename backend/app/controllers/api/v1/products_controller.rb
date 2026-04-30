module Api
  module V1
    class ProductsController < ApplicationController
      include Sortable
      include Exportable
      include Importable

      sortable_by "title", "handle", "vendor", "status", "product_type",
                  "updated_at", "created_at",
                  default: { updated_at: :desc }

      before_action :set_product, only: %i[show update destroy]

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

      def show
        authorize @product
        render json: { data: ProductSerializer.call(@product) }
      end

      def create
        authorize Product
        product = Product.new(product_params)
        product.save!
        render json: { data: ProductSerializer.call(product) }, status: :created
      end

      def update
        authorize @product
        @product.update!(product_params)
        render json: { data: ProductSerializer.call(@product) }
      end

      def destroy
        authorize @product
        @product.destroy!
        head :no_content
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
          scope.find_each { |p| p.update!(status: "archived"); count += 1 }
        when "activate"
          scope.find_each { |p| p.update!(status: "active"); count += 1 }
        when "delete"
          scope.find_each { |p| p.destroy!; count += 1 }
        else
          return render_error(400, "bad_request", "Unsupported action: #{action_type}")
        end

        render json: { data: { action: action_type, affected: count } }
      end

      private

      def filtered_scope
        scope = policy_scope(Product).includes(:variants)
        scope = scope.where("title ILIKE :q OR handle ILIKE :q", q: "%#{params[:search]}%") if params[:search].present?
        scope = scope.where(status: params[:status]) if params[:status].present?
        scope = scope.from_shopify if params[:from_shopify].to_s == "true"
        scope
      end

      def set_product
        @product = Product.find(params[:id])
      end

      def product_params
        params.require(:product).permit(
          :title, :handle, :status, :vendor, :product_type, :description,
          :seo_title, :seo_description, :template_suffix,
          :published_at, :published_scope, :gift_card,
          tags: [],
          variants_attributes: [
            :id, :sku, :title, :price, :compare_at_price, :cost_per_item,
            :barcode, :position, :_destroy,
            :option1, :option2, :option3,
            :weight, :weight_unit,
            :inventory_policy, :inventory_management,
            :requires_shipping, :taxable, :fulfillment_service,
            :hs_code, :country_of_origin
          ],
          product_options_attributes: [
            :id, :name, :position, :_destroy,
            product_option_values_attributes: [:id, :value, :position, :_destroy]
          ],
          product_images_attributes: [
            :id, :src, :alt, :position, :width, :height, :variant_id, :_destroy
          ]
        )
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
