module Accounting
  # Safely "deletes" a manual journal entry by posting a reversing entry.
  #
  # We never hard-delete journal data: removing rows would silently change
  # historical totals on trial balance, ledgers, P&L and balance sheet. Instead
  # we apply the same reversal pattern used elsewhere in the system —
  # JournalEntry#reverse! creates an opposite entry and flips the original to
  # status="reversed", so both rows remain visible in the audit trail but the
  # net effect on every report is zero.
  #
  # Only entries that the user actually created by hand (entry_type="manual")
  # and that are still posted may be reversed this way. Automatic entries
  # (sale, refund, etc.) must stay aligned with their source documents and
  # cannot be removed through this path.
  class ManualJournalEntryDeletion
    class NotManualError    < StandardError; end
    class NotPostedError    < StandardError; end
    class IsReversalError   < StandardError; end

    Result = Struct.new(:reversal, :original, keyword_init: true)

    def self.call(entry, actor: nil, request: nil)
      new(entry, actor: actor, request: request).call
    end

    def initialize(entry, actor: nil, request: nil)
      @entry   = entry
      @actor   = actor
      @request = request
    end

    def call
      raise NotManualError, "Only manual journal entries can be deleted." unless @entry.entry_type == "manual"
      raise NotPostedError, "Only posted entries can be deleted (status=#{@entry.status})." unless @entry.status == "posted"
      raise IsReversalError, "This entry is itself a reversal and cannot be reversed again. Delete or reverse the original instead." if @entry.reversal_of_id.present?

      reversal = nil
      ActiveRecord::Base.transaction do
        reversal = @entry.reverse!(description: "Manual deletion of \"#{@entry.description}\"")
        AuditLog.record(
          user:    @actor,
          action:  "accounting.journal.manual_delete",
          subject: @entry,
          request: @request,
          diff:    { reversal_journal_entry_id: reversal.id }
        )
      end
      Result.new(reversal: reversal, original: @entry.reload)
    end
  end
end
