require "csv"
require "caxlsx"

# Generic exporter: given a list of header => attribute|lambda pairs + an
# enumerable of records, produces CSV / JSON / XLSX bytes.
#
# Example:
#   rows = Product.order(:title)
#   columns = {
#     "Title"    => :title,
#     "Handle"   => :handle,
#     "Variants" => ->(p) { p.variants.size }
#   }
#   Exports::Generic.call(rows: rows, columns: columns, format: "csv")
module Exports
  class Generic
    MAX_ROWS = 50_000

    def self.call(rows:, columns:, format:)
      format = format.to_s.downcase
      case format
      when "csv"  then to_csv(rows, columns)
      when "json" then to_json(rows, columns)
      when "xlsx" then to_xlsx(rows, columns)
      else raise ArgumentError, "Unsupported format: #{format}"
      end
    end

    def self.to_csv(rows, columns)
      CSV.generate(headers: true) do |csv|
        csv << columns.keys
        each_row(rows) do |row|
          csv << columns.values.map { |attr| resolve(row, attr) }
        end
      end
    end

    def self.to_json(rows, columns)
      out = []
      each_row(rows) do |row|
        h = {}
        columns.each { |header, attr| h[header] = resolve(row, attr) }
        out << h
      end
      out.to_json
    end

    def self.to_xlsx(rows, columns)
      pkg = Axlsx::Package.new
      pkg.workbook.add_worksheet(name: "Export") do |sheet|
        sheet.add_row columns.keys
        each_row(rows) do |row|
          sheet.add_row columns.values.map { |attr| resolve(row, attr) }
        end
      end
      pkg.to_stream.read
    end

    def self.each_row(rows)
      count = 0
      rows.find_each(batch_size: 500) do |row|
        yield row
        count += 1
        break if count >= MAX_ROWS
      end
    rescue NoMethodError
      # If not ActiveRecord::Relation (e.g., plain array), fall back.
      rows.each do |row|
        yield row
        count += 1
        break if count >= MAX_ROWS
      end
    end

    def self.resolve(row, attr)
      case attr
      when Symbol, String then row.public_send(attr)
      when Proc then attr.call(row)
      else attr.to_s
      end
    end

    def self.mime_type(format)
      case format.to_s
      when "csv"  then "text/csv"
      when "json" then "application/json"
      when "xlsx" then "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
      else "application/octet-stream"
      end
    end
  end
end
