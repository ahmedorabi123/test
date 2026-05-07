module Crm
  module Shopify
    # Upserts a Shopify customers/create|update webhook payload into a Customer.
    class CustomerUpserter
      def self.call(payload)
        new(payload).call
      end

      def initialize(payload)
        @payload = payload.with_indifferent_access
      end

      def call
        shopify_id = @payload[:id].to_i
        return nil if shopify_id.zero?

        updated_at = parse_time(@payload[:updated_at])

        customer = ::Customer.find_or_initialize_by(shopify_customer_id: shopify_id)
        # Don't overwrite newer local state with stale Shopify payload.
        if customer.persisted? && customer.shopify_updated_at.present? && updated_at.present? &&
           customer.shopify_updated_at >= updated_at
          return customer
        end

        attrs = {
          email:              @payload[:email].presence,
          phone:              @payload[:phone].presence,
          first_name:         @payload[:first_name].presence,
          last_name:          @payload[:last_name].presence,
          tags:               normalize_tags(@payload[:tags]),
          default_address:    (@payload[:default_address].is_a?(Hash) ? @payload[:default_address].to_h : {}),
          addresses:          Array(@payload[:addresses]).map { |a| a.is_a?(Hash) ? a.to_h : {} },
          accepts_marketing:  accepts_email_marketing?,
          verified_email:     !!@payload[:verified_email],
          tax_exempt:         !!@payload[:tax_exempt],
          state:              @payload[:state].presence,
          note:               @payload[:note].presence,
          last_order_id:      @payload[:last_order_id].presence&.to_i,
          last_order_name:    @payload[:last_order_name].presence,
          orders_count:       @payload[:orders_count].to_i,
          total_spent:        (@payload[:total_spent] || 0).to_s.to_d,
          currency:           (@payload[:currency].presence || "EGP").upcase,
          source:             "shopify",
          shopify_updated_at: updated_at
        }
        customer.assign_attributes(attrs)
        customer.save!
        link_orders(customer, shopify_id)
        recompute_stats_if_needed(customer)
        customer
      rescue ActiveRecord::RecordNotUnique
        # Another concurrent process inserted the same shopify_customer_id between our
        # find_or_initialize_by and save!. Find the existing record and update it instead.
        customer = ::Customer.find_by!(shopify_customer_id: shopify_id)
        customer.update!(attrs)

        link_orders(customer, shopify_id)
        recompute_stats_if_needed(customer)

        customer
      end

      private

      def backfill_last_order(customer)
        last = customer.orders.order(placed_at: :desc).first
        return unless last
        customer.update_columns(last_order_at: last.placed_at,
                                last_order_name: customer.last_order_name.presence || last.order_number)
      end

      def accepts_email_marketing?
        consent = @payload[:email_marketing_consent]
        return consent[:state].to_s == "subscribed" if consent.is_a?(Hash)

        !!@payload[:accepts_marketing]
      end

      def recompute_stats_if_needed(customer)
        return unless customer.orders.exists?

        ::Crm::CustomerStatsRecomputer.call(customer)
      end

      def normalize_tags(raw)
        return [] if raw.blank?
        return raw if raw.is_a?(Array)
        raw.to_s.split(",").map(&:strip).reject(&:empty?)
      end

      def link_orders(customer, shopify_id)
        ::Order.where(shopify_customer_id: shopify_id, customer_id: nil)
               .update_all(customer_id: customer.id)
      end

      def parse_time(v)
        return nil if v.blank?
        v.is_a?(Time) || v.is_a?(ActiveSupport::TimeWithZone) ? v : Time.zone.parse(v.to_s)
      rescue ArgumentError
        nil
      end
    end
  end
end
