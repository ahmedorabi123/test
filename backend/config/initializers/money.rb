MoneyRails.configure do |config|
  config.default_currency = :egp
  config.rounding_mode = BigDecimal::ROUND_HALF_UP
end
