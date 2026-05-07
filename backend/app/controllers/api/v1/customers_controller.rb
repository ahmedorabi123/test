module Api
  module V1
    class CustomersController < ApplicationController
      include Sortable
      include Exportable
      include Importable

      sortable_by "created_at", "updated_at", "email", "first_name", "last_name",
                  "orders_count", "total_spent", "last_order_at", "source",
                  default: { last_order_at: :desc }

      before_action :set_customer, only: %i[show update destroy]

      # GET /api/v1/customers?search=&page=&per_page=&sort=&dir=
      def index
        authorize Customer
        scope = filtered_scope

        page     = [params[:page].to_i, 1].max
        per_page = params[:per_page].to_i
        per_page = 25  if per_page <= 0
        per_page = 200 if per_page > 200

        records = apply_sort(scope).offset((page - 1) * per_page).limit(per_page)
        total   = scope.count

        render json: {
          data: records.map { |c| CustomerSerializer.call(c) },
          meta: { page: page, per_page: per_page, total: total }
        }
      end

      # Shopify's Customers list behaves closest to "Last order" first for this
      # ERP surface; keep no-order customers at the end and make ties stable.
      def apply_sort(scope)
        if params[:sort].blank? || params[:sort].to_s == "last_order_at"
          dir = params[:dir].to_s.downcase == "asc" ? "ASC" : "DESC"
          scope.order(Arel.sql("customers.last_order_at #{dir} NULLS LAST, customers.created_at #{dir}, customers.id #{dir}"))
        else
          super
        end
      end

      # GET /api/v1/customers/:id
      def show
        authorize @customer
        render json: { data: CustomerSerializer.call(@customer, include_orders: true, include_last_order: true) }
      end

      # POST /api/v1/customers
      def create
        authorize Customer
        customer = Customer.new(customer_params)
        if customer.save
          AuditLog.record(user: current_user, action: "customer.created", subject: customer,
                          diff: customer.attributes.slice("email", "first_name", "last_name"),
                          request: request)
          render json: { data: CustomerSerializer.call(customer) }, status: :created
        else
          render_error(422, "unprocessable_entity", customer.errors.full_messages.join(", "))
        end
      end

      # PATCH /api/v1/customers/:id
      def update
        authorize @customer
        if @customer.update(customer_params)
          AuditLog.record(user: current_user, action: "customer.updated", subject: @customer,
                          diff: @customer.previous_changes, request: request)
          render json: { data: CustomerSerializer.call(@customer) }
        else
          render_error(422, "unprocessable_entity", @customer.errors.full_messages.join(", "))
        end
      end

      # DELETE /api/v1/customers/:id
      def destroy
        authorize @customer
        if @customer.orders.exists?
          return render_error(422, "unprocessable_entity", "Cannot delete customer with existing orders")
        end
        @customer.destroy!
        AuditLog.record(user: current_user, action: "customer.deleted", subject: @customer, diff: {}, request: request)
        head :no_content
      end

      # POST /api/v1/customers/bulk
      def bulk
        authorize Customer
        ids = Array(params[:ids])
        action_type = params[:action_type].to_s
        customers = Customer.where(id: ids)
        count = 0

        case action_type
        when "delete"
          customers.each do |c|
            next if c.orders.exists?
            c.destroy!
            count += 1
          end
        when "add_tag"
          tag = params.dig(:payload, :tag).to_s.strip
          return render_error(400, "bad_request", "tag required") if tag.blank?
          customers.find_each do |c|
            c.update!(tags: (c.tags + [tag]).uniq)
            count += 1
          end
        when "remove_tag"
          tag = params.dig(:payload, :tag).to_s.strip
          return render_error(400, "bad_request", "tag required") if tag.blank?
          customers.find_each do |c|
            c.update!(tags: c.tags - [tag])
            count += 1
          end
        else
          return render_error(400, "bad_request", "Unsupported action: #{action_type}")
        end

        render json: { data: { action: action_type, affected: count } }
      end

      private

      def filtered_scope
        scope = policy_scope(Customer)
        if params[:search].present?
          q = "%#{params[:search].to_s.strip}%"
          scope = scope.where(
            <<~SQL.squish,
              email ILIKE :q
              OR phone ILIKE :q
              OR first_name ILIKE :q
              OR last_name ILIKE :q
              OR (COALESCE(first_name, '') || ' ' || COALESCE(last_name, '')) ILIKE :q
            SQL
            q: q
          )
        end
        scope
      end

      def set_customer
        @customer = Customer.find(params[:id])
      end

      def customer_params
        params.require(:customer).permit(
          :email, :first_name, :last_name, :phone, :currency,
          :accepts_marketing, :tax_exempt, :verified_email, :state, :note,
          tags: [],
          default_address: {},
          addresses: [
            :id, :address1, :address2, :city, :province, :province_code,
            :country, :country_code, :zip, :phone, :company, :first_name,
            :last_name, :name, :default
          ]
        )
      end

      # -- Exportable / Importable hooks --
      def export_scope
        authorize Customer
        apply_sort(filtered_scope)
      end

      def export_columns
        {
          "First Name"          => :first_name,
          "Last Name"           => :last_name,
          "Email"               => :email,
          "Phone"               => :phone,
          "Total Spent"         => :total_spent,
          "Total Orders"        => :orders_count,
          "Currency"            => :currency,
          "Tags"                => ->(c) { c.tags.join(", ") },
          "Address1"            => ->(c) { c.default_address["address1"] },
          "City"                => ->(c) { c.default_address["city"] },
          "Country"             => ->(c) { c.default_address["country"] },
          "Zip"                 => ->(c) { c.default_address["zip"] },
          "Shopify Customer Id" => :shopify_customer_id,
          "Created At"          => :created_at
        }
      end

      def importer_class
        authorize Customer, :create?
        Imports::CustomersImporter
      end
    end
  end
end
