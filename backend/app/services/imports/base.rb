require "csv"

# Base importer. Subclasses implement:
#   - HEADERS  (Array<String>) — expected column names
#   - validate_row(row_hash, row_num) -> errors: Array, warnings: Array
#   - persist_row(row_hash)           -> :created | :updated
#
# Usage:
#   Imports::CustomersImporter.preview(csv_string)
#   Imports::CustomersImporter.commit(csv_string)
module Imports
  class Base
    HEADERS = [].freeze
    MAX_ROWS = 5_000

    def self.preview(csv_string)
      rows, parse_error = parse(csv_string)
      return { total: 0, valid: 0, errors: [{ row: 0, message: parse_error }], warnings: [], sample: [] } if parse_error

      errors   = []
      warnings = []
      sample   = []

      rows.each_with_index do |row, i|
        row_num = i + 2 # account for header
        row_errors, row_warnings = new.validate_row(row, row_num)
        errors.concat(row_errors)
        warnings.concat(row_warnings)
        sample << row if sample.size < 5
      end

      {
        total:    rows.size,
        valid:    rows.size - errors.map { |e| e[:row] }.uniq.size,
        errors:   errors,
        warnings: warnings,
        sample:   sample
      }
    end

    def self.commit(csv_string)
      rows, parse_error = parse(csv_string)
      raise ArgumentError, parse_error if parse_error

      created = 0
      updated = 0
      errors  = []

      rows.each_with_index do |row, i|
        row_num = i + 2
        row_errors, = new.validate_row(row, row_num)
        if row_errors.any?
          errors.concat(row_errors)
          next
        end
        begin
          result = new.persist_row(row)
          case result
          when :created then created += 1
          when :updated then updated += 1
          end
        rescue StandardError => e
          errors << { row: row_num, message: "#{e.class}: #{e.message}" }
        end
      end

      { created: created, updated: updated, errors: errors }
    end

    # Default no-op implementations (subclasses override).
    def validate_row(_row, _row_num)
      [[], []]
    end

    def persist_row(_row)
      :created
    end

    def self.parse(csv_string)
      return [nil, "Empty file"] if csv_string.blank?

      rows = []
      CSV.parse(csv_string, headers: true).each_with_index do |r, i|
        if i >= MAX_ROWS
          return [nil, "CSV exceeds max rows (#{MAX_ROWS})"]
        end
        rows << r.to_h
      end
      [rows, nil]
    rescue CSV::MalformedCSVError => e
      [nil, "Malformed CSV: #{e.message}"]
    end
  end
end
