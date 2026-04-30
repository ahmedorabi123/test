Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }

  # Death handler — when a job exhausts all retries, log to Rails + AuditLog
  # so ops can triage via the UI.
  config.death_handlers << ->(job, ex) do
    Rails.logger.error(
      "[Sidekiq DLQ] job=#{job['class']} args=#{job['args'].inspect} ex=#{ex.class}: #{ex.message}"
    )
    begin
      AuditLog.create!(
        action:       "job.dead",
        subject_type: "SidekiqJob",
        occurred_at:  Time.current,
        diff: {
          jid:   job["jid"],
          class: job["class"],
          args:  job["args"],
          error: ex.message,
          error_class: ex.class.name,
          queue: job["queue"]
        }
      )
    rescue StandardError => e
      Rails.logger.error("[Sidekiq DLQ] failed to write AuditLog: #{e.message}")
    end
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0") }
end

# Global default — 10 retries, exponential backoff (Sidekiq default).
Sidekiq.default_job_options = { "retry" => 10, "backtrace" => 10 }
