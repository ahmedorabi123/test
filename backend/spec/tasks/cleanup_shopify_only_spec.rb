require "rails_helper"
require "rake"

RSpec.describe "db:cleanup:shopify_only", type: :task do
  before(:all) do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  let(:task_name) { "db:cleanup:shopify_only" }

  def task
    Rake::Task[task_name].tap(&:reenable)
  end

  it "aborts without CLEANUP_CONFIRM" do
    ENV.delete("CLEANUP_CONFIRM")
    expect { task.invoke }.to raise_error(SystemExit)
  end

  context "with confirm + DRY_RUN" do
    around do |ex|
      orig = { c: ENV["CLEANUP_CONFIRM"], d: ENV["DRY_RUN"], s: ENV["SKIP_BACKFILL"] }
      ENV["CLEANUP_CONFIRM"] = "YES_I_MEAN_IT"
      ENV["DRY_RUN"]         = "1"
      ENV["SKIP_BACKFILL"]   = "1"
      ex.run
    ensure
      ENV["CLEANUP_CONFIRM"] = orig[:c]
      ENV["DRY_RUN"]         = orig[:d]
      ENV["SKIP_BACKFILL"]   = orig[:s]
    end

    it "runs without deleting anything (rolled back)" do
      shopify_order = create(:order, shopify_order_id: "gid://shopify/Order/123", financial_status: "paid", total_price: 50)
      expect {
        task.invoke
      }.not_to change { Order.where(id: shopify_order.id).count }
    end
  end
end
