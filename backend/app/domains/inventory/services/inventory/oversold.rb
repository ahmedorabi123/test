module Inventory
  class Oversold < StandardError
    attr_reader :shortages

    def initialize(shortages)
      @shortages = shortages
      super(build_message)
    end

    private

    def build_message
      return "Insufficient stock" if shortages.blank?

      details = shortages.map do |row|
        sku = row[:sku].presence || row[:title].presence || row[:variant_id]
        "#{sku}: requested #{row[:requested]}, available #{row[:available]}"
      end
      "Insufficient stock (#{details.join('; ')})"
    end
  end
end