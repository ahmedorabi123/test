module Crm
  class CustomerStatsRecomputer
    COUNTABLE_STATUSES = %w[pending processing fulfilled].freeze
    SPENT_FINANCIAL_STATUSES = %w[paid partially_paid].freeze

    def self.call(customer)
      new(customer).call
    end

    def initialize(customer)
      @customer = customer
    end

    def call
      orders = @customer.orders.where(status: COUNTABLE_STATUSES)
      last_order = orders.order(placed_at: :desc).first

      @customer.update_columns(
        orders_count: orders.count,
        total_spent: orders.where(financial_status: SPENT_FINANCIAL_STATUSES)
           .sum(:total_price),
        last_order_name: last_order&.order_number,
        last_order_at: last_order&.placed_at,
        updated_at: Time.current
      )

      @customer
    end
  end
end