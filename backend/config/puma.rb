# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
threads_count = ENV.fetch("RAILS_MAX_THREADS", 3)
threads threads_count, threads_count

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT", 3000)

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
# In other environments, only set the PID file if requested.
pidfile ENV["PIDFILE"] if ENV["PIDFILE"]

# ─── Post-boot Shopify bootstrap ──────────────────────────────────────────────
# Runs `rake bootstrap:run` AFTER Puma has bound the port and started accepting
# requests. This avoids Render's port-scan timeout (which kills the service if
# it doesn't bind within ~90s). The bootstrap is idempotent — it auto-skips
# when the DB already has Shopify data.
#
# Disable with SKIP_BOOTSTRAP=true.
unless %w[true 1].include?(ENV["SKIP_BOOTSTRAP"].to_s.downcase)
  on_worker_boot do
    Thread.new do
      sleep 10  # give Puma a moment to settle
      begin
        require "rake"
        Rails.application.load_tasks unless Rake::Task.task_defined?("bootstrap:run")
        Rake::Task["bootstrap:run"].reenable rescue nil
        Rake::Task["bootstrap:run"].invoke
      rescue => e
        Rails.logger.error("[bootstrap] background run failed: #{e.class}: #{e.message}")
        warn "[bootstrap] background run failed: #{e.class}: #{e.message}"
      end
    end
  end
end
