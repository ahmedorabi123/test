# frozen_string_literal: true

namespace :refunds do
  desc "Report possible duplicate manual refunds. DRY_RUN=true by default; writes tmp/refund_duplicate_report.csv"
  task dedupe_report: :environment do
    require "csv"

    dry_run = ENV.fetch("DRY_RUN", "true") != "false"
    output_path = Rails.root.join("tmp", "refund_duplicate_report.csv")
    scope = Refund.where(shopify_refund_id: nil)
    scope = scope.where(kind: ENV["KIND"]) if ENV["KIND"].present?
    scope = scope.where("created_at >= ?", Time.zone.parse(ENV["FROM"])) if ENV["FROM"].present?
    scope = scope.where("created_at <= ?", Time.zone.parse(ENV["TO"])) if ENV["TO"].present?

    groups = scope
      .select("order_id, amount, currency, COALESCE(reason, '') AS normalized_reason, COALESCE(content_hash, '') AS normalized_hash, COUNT(*) AS duplicate_count, MIN(created_at) AS first_seen, MAX(created_at) AS last_seen")
      .group("order_id, amount, currency, COALESCE(reason, ''), COALESCE(content_hash, '')")
      .having("COUNT(*) > 1")
      .order("duplicate_count DESC")

    CSV.open(output_path, "w") do |csv|
      csv << %w[group_order_id amount currency reason content_hash duplicate_count first_seen last_seen keep_refund_id duplicate_refund_ids]
      groups.each do |group|
        refunds = scope.where(order_id: group.order_id, amount: group.amount, currency: group.currency)
        refunds = refunds.where(reason: nil) if group.normalized_reason.blank?
        refunds = refunds.where(reason: group.normalized_reason) if group.normalized_reason.present?
        refunds = refunds.where(content_hash: nil) if group.normalized_hash.blank?
        refunds = refunds.where(content_hash: group.normalized_hash) if group.normalized_hash.present?
        ordered = refunds.order(:created_at, :id).to_a
        keeper = ordered.first
        duplicates = ordered.drop(1)
        csv << [group.order_id, group.amount, group.currency, group.normalized_reason, group.normalized_hash, group.duplicate_count, group.first_seen, group.last_seen, keeper&.id, duplicates.map(&:id).join("|")]
      end
    end

    puts "Refund duplicate report written to #{output_path}"
    puts "Duplicate groups: #{groups.size}"
    puts "DRY_RUN=#{dry_run}. No refunds were deleted or modified."
    puts "Review the CSV before any remediation. This task intentionally does not hard-delete records."
  end
end
