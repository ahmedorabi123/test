# Inventory::TransferStock
#
# Atomically moves units of a variant from one warehouse to another.
# Writes two StockMovement records (out from source, in to dest) sharing
# the given `reference` so they can be paired in the audit trail.
#
# Raises if source has insufficient on-hand.
class Inventory::TransferStock
  class InsufficientStock < StandardError; end

  def self.call(variant:, from_warehouse:, to_warehouse:, quantity:, reference: nil, reason: "transfer")
    new(variant, from_warehouse, to_warehouse, quantity.to_i, reference, reason).call
  end

  def initialize(variant, from_warehouse, to_warehouse, quantity, reference, reason)
    @variant         = variant
    @from_warehouse  = from_warehouse
    @to_warehouse    = to_warehouse
    @quantity        = quantity
    @reference       = reference
    @reason          = reason
  end

  def call
    raise ArgumentError, "quantity must be positive" if @quantity <= 0
    raise ArgumentError, "warehouses must differ" if @from_warehouse.id == @to_warehouse.id

    StockItem.transaction do
      from_si = StockItem.lock.find_by!(variant: @variant, warehouse: @from_warehouse)
      to_si   = StockItem.find_or_create_by!(variant: @variant, warehouse: @to_warehouse) do |si|
        si.quantity_on_hand = 0
      end
      to_si.lock!

      # Honour reservations: only transfer what is actually available
      # (on_hand - reserved - unavailable). This prevents transfers from
      # cannibalising stock already promised to pending/processing orders.
      available = from_si.available
      if available < @quantity
        raise InsufficientStock,
              "Cannot transfer #{@quantity}: only #{available} available at #{@from_warehouse.code} " \
              "(on_hand=#{from_si.quantity_on_hand}, reserved=#{from_si.quantity_reserved}, " \
              "unavailable=#{from_si.quantity_unavailable})"
      end

      Inventory::WriteMovement.call(
        stock_item: from_si,
        delta:      -@quantity,
        reason:     @reason,
        reference:  @reference
      )
      Inventory::WriteMovement.call(
        stock_item: to_si,
        delta:      @quantity,
        reason:     @reason,
        reference:  @reference
      )

      [from_si.reload, to_si.reload]
    end
  end
end
