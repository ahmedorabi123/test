module Imports
  # Orders importer for manual backfill.
  # Shopify orders export CSV — minimal subset of columns.
  #
  # Required: Name, Financial Status, Currency, Total, Created at
  # Optional: Email, Billing Name, Fulfillment Status, Lineitem sku,
  #           Lineitem quantity, Lineitem price, Lineitem name, Notes
  #
  # Rows sharing the same "Name" are grouped into one order (Shopify's
  # multi-line export format).
  class OrdersImporter < Base
    HEADERS = ["Name", "Currency", "Total", "Created at"].freeze

    def validate_row(row, row_num)
      errors = []
      if row["Name"].blank?
        errors << { row: row_num, message: "Name (order number) is required" }
      end
      if row["Total"].present? && !row["Total"].to_s.match?(/\A-?\d+(\.\d+)?\z/)
        errors << { row: row_num, message: "Total must be numeric" }
      end
      [errors, []]
    end

    def self.commit(csv_string)
      rows, parse_error = parse(csv_string)
      raise ArgumentError, parse_error if parse_error

      created = 0
      errors  = []

      # Pre-validate
      rows.each_with_index do |row, i|
        row_errors, = new.validate_row(row, i + 2)
        errors.concat(row_errors)
      end

      bad_rows = errors.map { |e| e[:row] }.to_set
      groups   = rows.each_with_object({}) do |row, h|
        next if row["Name"].blank?
        (h[row["Name"]] ||= []) << row
      end

      groups.each do |order_name, lines|
        group_row_nums = lines.map { |r| rows.index(r) + 2 }
        next if (group_row_nums & bad_rows.to_a).any?
        next if ::Order.where("external_number = :n OR order_number = :n", n: order_name).exists?

        begin
          first = lines.first
          line_items = lines.filter_map do |row|
            next if row["Lineitem sku"].blank? && row["Lineitem name"].blank?
            variant = row["Lineitem sku"].present? ? Variant.find_by(sku: row["Lineitem sku"]) : nil
            {
              sku:           row["Lineitem sku"],
              variant_id:    variant&.id,
              title:         row["Lineitem name"] || variant&.product&.title || row["Lineitem sku"].to_s,
              variant_title: variant&.title,
              quantity:      row["Lineitem quantity"].to_i.nonzero? || 1,
              price:         row["Lineitem price"].to_s.presence || "0"
            }
          end

          # If no line items, create a single dummy line from Total
          if line_items.empty?
            line_items << {
              title:    "Imported order #{order_name}",
              quantity: 1,
              price:    first["Total"].to_s.presence || "0"
            }
          end

          Sales::ManualOrderCreator.call(
            source:          "manual",
            currency:        (first["Currency"].presence || "USD").upcase,
            customer_email:  first["Email"],
            customer_name:   first["Billing Name"] || first["Name"],
            notes:           "Imported from Shopify export (#{order_name})",
            mark_paid:       %w[paid partially_paid].include?(first["Financial Status"].to_s.downcase),
            line_items:      line_items
          )
          created += 1
        rescue StandardError => e
          errors << { row: 0, message: "Order #{order_name}: #{e.class}: #{e.message}" }
        end
      end

      { created: created, updated: 0, errors: errors.uniq }
    end
  end
end
