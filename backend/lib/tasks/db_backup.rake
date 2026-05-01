namespace :db do
  # ── Backup ──────────────────────────────────────────────────────────────────
  # Usage (inside container or via docker compose exec):
  #   rails db:backup
  #   rails db:backup[my_label]
  #
  # Creates: db/backups/erp_YYYYMMDD_HHMMSS_<label>.dump (pg_dump custom format)
  # The db/backups/ directory is git-ignored but lives inside the project so
  # it persists across `docker compose down -v` (volume wipes).
  #
  desc "Dump the development DB to db/backups/ (pg_dump custom format, restoreable with db:restore)"
  task :backup, [:label] => :environment do |_, args|
    label    = args[:label].presence || "manual"
    ts       = Time.now.strftime("%Y%m%d_%H%M%S")
    dir      = Rails.root.join("db", "backups")
    FileUtils.mkdir_p(dir)
    filename = dir.join("erp_#{ts}_#{label}.dump")

    cfg      = ActiveRecord::Base.connection_db_config.configuration_hash
    host     = cfg[:host]     || ENV.fetch("DB_HOST",     "localhost")
    port     = cfg[:port]     || ENV.fetch("DB_PORT",     5432)
    user     = cfg[:username] || ENV.fetch("DB_USERNAME", "postgres")
    dbname   = cfg[:database] || "erp_development"
    password = cfg[:password] || ENV.fetch("DB_PASSWORD", "")

    env = { "PGPASSWORD" => password.to_s }
    cmd = ["pg_dump", "-Fc", "-h", host.to_s, "-p", port.to_s, "-U", user.to_s, "-d", dbname.to_s, "-f", filename.to_s]

    puts "[db:backup] Dumping #{dbname} → #{filename} ..."
    success = system(env, *cmd)
    if success
      size_mb = (File.size(filename) / 1_048_576.0).round(1)
      puts "[db:backup] Done. #{filename.basename} (#{size_mb} MB)"
      puts "[db:backup] Restore with: rails 'db:restore[#{filename.basename}]'"
    else
      abort "[db:backup] pg_dump failed — is pg_dump installed in the container?"
    end
  end

  # ── Restore ─────────────────────────────────────────────────────────────────
  # Usage:
  #   rails 'db:restore[erp_20260501_120000_shopify.dump]'
  #   rails 'db:restore[/absolute/path/to/file.dump]'
  #
  desc "Restore DB from a dump file created by db:backup"
  task :restore, [:filename] => :environment do |_, args|
    abort "[db:restore] Usage: rails 'db:restore[filename.dump]'" unless args[:filename].present?

    path = Pathname.new(args[:filename])
    path = Rails.root.join("db", "backups", path) unless path.absolute?
    abort "[db:restore] File not found: #{path}" unless path.exist?

    cfg      = ActiveRecord::Base.connection_db_config.configuration_hash
    host     = cfg[:host]     || ENV.fetch("DB_HOST",     "localhost")
    port     = cfg[:port]     || ENV.fetch("DB_PORT",     5432)
    user     = cfg[:username] || ENV.fetch("DB_USERNAME", "postgres")
    dbname   = cfg[:database] || "erp_development"
    password = cfg[:password] || ENV.fetch("DB_PASSWORD", "")

    env = { "PGPASSWORD" => password.to_s }

    # Terminate existing connections then drop+recreate
    puts "[db:restore] Dropping #{dbname}..."
    ActiveRecord::Base.connection.disconnect!
    system(env, "dropdb", "-h", host.to_s, "-p", port.to_s, "-U", user.to_s, "--if-exists", dbname.to_s)
    system(env, "createdb", "-h", host.to_s, "-p", port.to_s, "-U", user.to_s, dbname.to_s)

    puts "[db:restore] Restoring from #{path.basename} ..."
    cmd = ["pg_restore", "-h", host.to_s, "-p", port.to_s, "-U", user.to_s, "-d", dbname.to_s, "--no-owner", "--no-privileges", "-j", "4", path.to_s]
    success = system(env, *cmd)
    if success
      puts "[db:restore] Done. You may need to run: rails db:migrate"
    else
      # pg_restore exits non-zero for warnings (e.g. owner mismatch) — check manually
      puts "[db:restore] Restore finished (check above for any non-fatal warnings)."
    end
  end

  # ── List backups ─────────────────────────────────────────────────────────────
  desc "List available backups in db/backups/"
  task :backups do
    dir = Rails.root.join("db", "backups")
    if !dir.exist? || dir.children.none? { |f| f.extname == ".dump" }
      puts "[db:backups] No backups found in #{dir}"
    else
      puts "[db:backups] Available backups in #{dir}:"
      dir.glob("*.dump").sort.each do |f|
        size_mb = (File.size(f) / 1_048_576.0).round(1)
        puts "  #{f.basename}  (#{size_mb} MB)"
      end
    end
  end
end
