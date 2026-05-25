require "rails_helper"
require "rake"

RSpec.describe "db:cleanup:manual_only", type: :task do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:task_name) { "db:cleanup:manual_only" }

  def task
    Rake::Task[task_name].tap(&:reenable)
  end

  it "aborts without CLEANUP_CONFIRM" do
    ENV.delete("CLEANUP_CONFIRM")
    expect { task.invoke }.to raise_error(SystemExit)
  end

  context "with confirm + DRY_RUN" do
    around do |ex|
      orig = ENV.to_hash.slice("CLEANUP_CONFIRM", "DRY_RUN", "SKIP_CATCHUP")
      ENV["CLEANUP_CONFIRM"] = "YES_I_MEAN_IT"
      ENV["DRY_RUN"]         = "1"
      ENV["SKIP_CATCHUP"]    = "1"
      ex.run
    ensure
      ENV["CLEANUP_CONFIRM"] = orig["CLEANUP_CONFIRM"]
      ENV["DRY_RUN"]         = orig["DRY_RUN"]
      ENV["SKIP_CATCHUP"]    = orig["SKIP_CATCHUP"]
    end

    it "does not delete Shopify-origin orders (DRY_RUN rolls back) and does not change Shopify counts" do
      shopify_order = create(:order, shopify_order_id: "gid://shopify/Order/999", financial_status: "paid", total_price: 25)
      before_count  = Order.shopify_origin.count
      expect {
        task.invoke
      }.not_to change { Order.where(id: shopify_order.id).count }
      expect(Order.shopify_origin.count).to eq(before_count)
    end
  end
end
