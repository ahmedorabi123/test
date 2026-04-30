module Imports
  # Showroom/consignment sales importer.
  # CSV where each row is a single line item. Rows with the same "Order #"
  # are grouped into one manual order with source = "showroom".
  #
  # Required headers: Order #, SKU, Quantity, Price
  # Optional headers: Customer Email, Customer Name, Warehouse Code, Notes
  class ShowroomSalesImporter < Base
    HEADERS = ["Order #", "SKU", "Quantity", "Price"].freeze

    def validate_row(row, row_num)
      errors   = []
      warnings = []

      errors << { row: row_num, message: "Order # is required" } if row["Order #"].blank?
      errors << { row: row_num, message: "SKU is required" }     if row["SKU"].blank?

      errors << { row: row_num, message: "Quantity must be positive" } if row["Quantity"].to_i <= 0
      unless row["Price"].to_s.match?(/\A\d+(\.\d+)?\z/)
        errors << { row: row_num, message: "Price must be numeric" }
      end

      if row["SKU"].present? && !Variant.exists?(sku: row["SKU"])
        warnings << { row: row_num, message: "SKU #{row["SKU"]} not in catalog" }
      end

      [errors, warnings]
    end

    def self.commit(csv_string)
      rows, parse_error = parse(csv_string)
      raise ArgumentError, parse_error if parse_error

      created = 0
      errors  = []

      # Validate each row
      rows.each_with_index do |row, i|
        row_errors, = new.validate_row(row, i + 2)
        errors.concat(row_errors)
      end

      # Group by order number; skip orders where any line errored
      bad_rows = errors.map { |e| e[:row] }.to_set
      grouped  = rows.each_with_index.group_by { |_, i| _1.is_a?(Hash) ? _1["Order #"] : nil }

      groups = rows.each_with_object({}) do |row, h|
        next if row["Order #"].blank?
        (h[row["Order #"]] ||= []) << row
      end

      # Filter out groups with any invalid row (track row-numbers per group)
      groups.each do |order_num, lines|
        group_row_nums = lines.map { |r| rows.index(r) + 2 }
        next if (group_row_nums & bad_rows.to_a).any?

        begin
          first     = lines.first
          warehouse = Warehouse.find_by(code: first["Warehouse Code"]) if first["Warehouse Code"].present?
          line_items = lines.map do |row|
            variant = Variant.find_by(sku: row["SKU"])
            {
              sku:           row["SKU"],
              variant_id:    variant&.id,
              title:         variant&.product&.title || row["SKU"],
              variant_title: variant&.title,
              quantity:      row["Quantity"].to_i,
              price:         row["Price"].to_s
            }
          end

          Sales::ManualOrderCreator.call(
            source:         "showroom",
            currency:       "USD",
            customer_email: first["Customer Email"],
            customer_name:  first["Customer Name"],
            notes:          first["Notes"] || "Imported showroom sale #{order_num}",
            location_id:    warehouse&.shopify_location_id,
            mark_paid:      true,
            line_items:     line_items
          )
          created += 1
        rescue StandardError => e
          errors << { row: 0, message: "Order #{order_num}: #{e.class}: #{e.message}" }
        end
      end

      { created: created, updated: 0, errors: errors.uniq }
    end
  end
end
