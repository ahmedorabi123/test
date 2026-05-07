namespace :crm do
  desc "Recompute denormalized customer order statistics from local orders"
  task recompute_customer_stats: :environment do
    total = 0
    Customer.find_each do |customer|
      Crm::CustomerStatsRecomputer.call(customer)
      total += 1
    end
    puts "Recomputed customer stats for #{total} customers"
  end
end