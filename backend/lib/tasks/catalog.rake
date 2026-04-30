namespace :catalog do
  namespace :shopify do
    desc "Backfill products from Shopify Admin API into the ERP catalog"
    task backfill_products: :environment do
      count = Catalog::Shopify::ProductBackfillService.call
      puts "Imported/updated #{count} products from Shopify."
    end
  end
end
