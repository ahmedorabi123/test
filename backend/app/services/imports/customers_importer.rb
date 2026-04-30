# Shopify-compatible customer CSV import.
#
# Expected headers (matches Shopify's customer export CSV):
#   First Name, Last Name, Email, Company, Address1, Address2, City,
#   Province, Province Code, Country, Country Code, Zip, Phone,
#   Accepts Email Marketing, Total Spent, Total Orders, Tags, Note,
#   Tax Exempt
#
# A row is matched by Email (unique). Missing email => error.
module Imports
  class CustomersImporter < Base
    HEADERS = [
      "First Name", "Last Name", "Email", "Company",
      "Address1", "Address2", "City", "Province", "Province Code",
      "Country", "Country Code", "Zip", "Phone",
      "Accepts Email Marketing", "Total Spent", "Total Orders",
      "Tags", "Note", "Tax Exempt"
    ].freeze

    def validate_row(row, row_num)
      errors = []
      warnings = []

      email = row["Email"].to_s.strip.downcase
      if email.blank?
        errors << { row: row_num, message: "Email is required" }
      elsif email !~ URI::MailTo::EMAIL_REGEXP
        errors << { row: row_num, message: "Email '#{email}' is not valid" }
      end

      first = row["First Name"].to_s.strip
      last  = row["Last Name"].to_s.strip
      if first.blank? && last.blank?
        warnings << { row: row_num, message: "Customer has no name" }
      end

      [errors, warnings]
    end

    def persist_row(row)
      email = row["Email"].to_s.strip.downcase
      customer = Customer.find_or_initialize_by(email: email)
      was_new  = customer.new_record?

      address = {
        "address1"     => row["Address1"],
        "address2"     => row["Address2"],
        "city"         => row["City"],
        "province"     => row["Province"],
        "province_code" => row["Province Code"],
        "country"      => row["Country"],
        "country_code" => row["Country Code"],
        "zip"          => row["Zip"],
        "company"      => row["Company"]
      }.compact

      tags = row["Tags"].to_s.split(",").map(&:strip).reject(&:blank?)

      customer.assign_attributes(
        first_name:      row["First Name"].to_s.strip.presence,
        last_name:       row["Last Name"].to_s.strip.presence,
        phone:           row["Phone"].to_s.strip.presence,
        default_address: address,
        tags:            tags
      )
      customer.save!
      was_new ? :created : :updated
    end
  end
end
