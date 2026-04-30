module Purchases
  module Serializers
    class SupplierSerializer
      def self.call(s)
        {
          id:            s.id,
          name:          s.name,
          email:         s.email,
          phone:         s.phone,
          currency:      s.currency,
          status:        s.status,
          address:       s.address,
          tax_id:        s.tax_id,
          payment_terms: s.payment_terms,
          notes:         s.notes,
          created_at:    s.created_at,
          updated_at:    s.updated_at
        }
      end
    end
  end
end

SupplierSerializer = Purchases::Serializers::SupplierSerializer
