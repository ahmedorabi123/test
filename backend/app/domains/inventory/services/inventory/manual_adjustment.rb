module Inventory
  # Applies a manual stock adjustment with an explicit business reason and
  # optionally posts an accounting journal entry. Returns the StockMovement.
  #
  # adjustment_reason values:
  #   "count"      - cycle count true-up (no accounting impact)
  #   "damage"     - damaged goods removed from inventory (no journal yet
  #                  unless flagged as write_off; tracked for audit)
  #   "write_off"  - posts DR 5900 Inventory Write-offs / CR 1200 Inventory
  #   "correction" - data-entry correction (no accounting impact)
  #
  # Idempotency for the journal posting is keyed by the underlying
  # StockMovement.id: idempotency_key = "inv-adjust-{movement.id}".
  class ManualAdjustment
    REASONS = %w[count damage write_off correction].freeze

    class InvalidReason < StandardError; end

    def self.call(...)
      new(...).call
    end

    def initialize(stock_item:, delta:, adjustment_reason:, note: nil, actor: nil)
      @stock_item        = stock_item
      @delta             = delta.to_i
      @adjustment_reason = adjustment_reason.to_s
      @note              = note.to_s
      @actor             = actor
    end

    def call
      raise InvalidReason, "adjustment_reason must be one of #{REASONS.join(', ')}" \
        unless REASONS.include?(@adjustment_reason)
      return nil if @delta.zero?

      movement = Inventory::WriteMovement.call(
        stock_item: @stock_item,
        delta:      @delta,
        reason:     "adjusted",
        note:       audit_note
      )

      if movement && @adjustment_reason == "write_off" && @delta.negative?
        cost_result = Inventory::ConsumeCostLayers.call(
          stock_item: @stock_item,
          quantity: @delta.abs,
          reference: movement
        )
        post_write_off_journal(movement, cost_result)
      end

      if @actor && movement
        AuditLog.create!(
          user_id:      @actor.id,
          action:       "inventory.adjusted",
          subject_type: "StockItem",
          subject_id:   @stock_item.id,
          diff:         {
            delta:             @delta,
            adjustment_reason: @adjustment_reason,
            note:              @note,
            movement_id:       movement.id
          },
          occurred_at:  Time.current
        )
      end

      movement
    end

    private

    def audit_note
      [ "[#{@adjustment_reason}]", @note ].reject(&:blank?).join(" ")
    end

    def post_write_off_journal(movement, cost_result)
      variant = @stock_item.variant
      if cost_result.zero?
        AuditLog.create!(
          action:       "inventory.write_off_zero_cost",
          subject_type: "StockMovement",
          subject_id:   movement.id,
          diff:         { variant_id: variant&.id, sku: variant&.sku, qty: @delta.abs, source: cost_result.source },
          occurred_at:  Time.current
        )
        return
      end

      total = cost_result.total_cost
      currency = @stock_item.warehouse&.currency.presence || "EGP"
      idem_key = "inv-adjust-#{movement.id}"
      return if JournalEntry.exists?(idempotency_key: idem_key)

      ensure_write_off_account!

      JournalEntry.post!(
        {
          entry_date:      Date.current,
          description:     "Inventory write-off – #{variant&.sku || variant&.id}",
          currency:        currency,
          source_type:     "stock_movement",
          source_id:       movement.id,
          entry_type:      "adjustment",
          idempotency_key: idem_key
        },
        [
          { account_code: "5900", side: "debit",  amount: total,
            description: "Inventory write-off (#{@delta.abs} × #{variant&.sku})" },
          { account_code: "1200", side: "credit", amount: total,
            description: "Inventory written off (#{@delta.abs} × #{variant&.sku})" }
        ]
      )
    end

    def ensure_write_off_account!
      return if Account.exists?(code: "5900")
      Account.create!(
        code:         "5900",
        name:         "Inventory Write-offs",
        account_type: "expense",
        normal_side:  "debit",
        active:       true
      )
    end
  end
end
