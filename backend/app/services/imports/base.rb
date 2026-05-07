require "csv"
require "roo"

# Base importer. Subclasses implement:
#   - HEADERS  (Array<String>) — expected column names
#   - validate_row(row_hash, row_num) -> errors: Array, warnings: Array
#   - persist_row(row_hash)           -> :created | :updated
#
# Usage:
#   Imports::CustomersImporter.preview(input)
#   Imports::CustomersImporter.commit(input)
#
# `input` is either a CSV string OR an uploaded file object responding to
# #read and #original_filename (XLSX/XLS detected by extension).
module Imports
  class Base
    HEADERS = [].freeze
    MAX_ROWS = 5_000

    XLSX_EXTENSIONS = %w[.xlsx .xls].freeze

    def self.preview(input)
      rows, parse_error = parse(input)
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

    def self.commit(input)
      rows, parse_error = parse(input)
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

    def self.parse(input)
      return [nil, "Empty file"] if input.nil? || (input.respond_to?(:blank?) && input.blank?)

      filename = input.respond_to?(:original_filename) ? input.original_filename.to_s : ""
      ext = File.extname(filename).downcase

      if XLSX_EXTENSIONS.include?(ext) || (input.respond_to?(:content_type) && input.content_type.to_s.match?(/sheet|excel/))
        parse_xlsx(input)
      else
        csv_string = input.respond_to?(:read) ? input.read.to_s : input.to_s
        csv_string.force_encoding("UTF-8") if csv_string.respond_to?(:force_encoding)
        parse_csv(csv_string)
      end
    end

    def self.parse_csv(csv_string)
      return [nil, "Empty file"] if csv_string.blank?

      rows = []
      CSV.parse(csv_string, headers: true).each_with_index do |r, i|
        return [nil, "CSV exceeds max rows (#{MAX_ROWS})"] if i >= MAX_ROWS

        rows << r.to_h
      end
      [rows, nil]
    rescue CSV::MalformedCSVError => e
      [nil, "Malformed CSV: #{e.message}"]
    end

    def self.parse_xlsx(file)
      tmp = Tempfile.new(["import", File.extname(file.original_filename.to_s)])
      tmp.binmode
      tmp.write(file.read)
      tmp.rewind

      spreadsheet = Roo::Spreadsheet.open(tmp.path)
      sheet = spreadsheet.sheet(0)
      raw_headers = sheet.row(1).map { |h| h.to_s.strip }
      rows = []
      (2..sheet.last_row).each_with_index do |row_idx, i|
        return [nil, "XLSX exceeds max rows (#{MAX_ROWS})"] if i >= MAX_ROWS

        values = sheet.row(row_idx)
        next if values.all? { |v| v.nil? || v.to_s.strip.empty? }

        rows << raw_headers.zip(values.map { |v| v.is_a?(Numeric) ? v.to_s : v.to_s.strip }).to_h
      end
      [rows, nil]
    rescue StandardError => e
      [nil, "Malformed spreadsheet: #{e.message}"]
    ensure
      tmp&.close
      tmp&.unlink
    end
  end
end
