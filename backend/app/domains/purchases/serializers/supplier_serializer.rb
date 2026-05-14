module Purchases
  module Serializers
    class SupplierSerializer
      def self.call(s, include_summary: false)
        payload = {
          id:            s.id,
          supplier_code: s.respond_to?(:supplier_code) ? s.supplier_code : nil,
          name:          s.name,
          kind:          s.respond_to?(:kind) ? s.kind : nil,
          email:         s.email,
          phone:         s.phone,
          currency:      s.currency,
          status:        s.status,
          lead_time_days: s.respond_to?(:lead_time_days) ? s.lead_time_days : nil,
          address:       s.address,
          tax_id:        s.tax_id,
          payment_terms: s.payment_terms,
          notes:         s.notes,
          created_at:    s.created_at,
          updated_at:    s.updated_at
        }
        payload[:balance_summary] = balance_summary(s) if include_summary
        payload.compact
      end

      def self.balance_summary(s)
        purchase_orders = s.purchase_orders
        non_cancelled = purchase_orders.where.not(status: "cancelled")
        {
          purchase_orders_count: purchase_orders.count,
          total_ordered: non_cancelled.sum(:total).to_s,
          received_total: non_cancelled.where(status: "received").sum(:total).to_s,
          open_total: non_cancelled.where(status: %w[draft ordered partial]).sum(:total).to_s
        }
      end
    end
  end
end

SupplierSerializer = Purchases::Serializers::SupplierSerializer
