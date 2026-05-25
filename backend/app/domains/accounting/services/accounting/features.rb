module Accounting
  # Feature flags for the accounting domain.
  #
  # cogs_enabled?:
  #   When false (default), all COGS journal posting and its reversal are
  #   suppressed. The business does not track real COGS yet, so fulfillments
  #   only affect inventory; revenue is posted on mark-paid via
  #   PostSaleJournalHandler. Flip ACCOUNTING_COGS_ENABLED=true to re-enable.
  module Features
    module_function

    def cogs_enabled?
      ENV.fetch("ACCOUNTING_COGS_ENABLED", "false") == "true"
    end
  end
end
