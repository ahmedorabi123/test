module Inventory
  # Atomically posts a multi-variant stock transfer between two warehouses.
  #
  # Creates a +StockTransfer+ header row, one +StockTransferLine+ per
  # variant, and a pair of immutable +StockMovement+ rows per line
  # (one out from source, one in to destination), sharing the
  # +StockTransferLine+ as their +reference+ so they can be paired in the
  # audit trail.
  #
  # All writes happen inside a single transaction. If any line fails (e.g.
  # insufficient stock at source) the entire batch rolls back — Phase 1 does
  # not support partial transfers.
  #
  # Shopify-origin enforcement: either warehouse being Shopify-origin, or any
  # line resolving to a Shopify-origin StockItem on either side, raises
  # +ReadOnlyOrigin+ and the controller surfaces 423
  # `read_only_shopify_resource`.
  class PostStockTransfer
    class InsufficientStock < StandardError
      attr_reader :variant_id, :available, :requested
      def initialize(message, variant_id:, available:, requested:)
        super(message)
        @variant_id = variant_id
        @available  = available
        @requested  = requested
      end
    end

    class ReadOnlyOrigin < StandardError; end
    class InvalidInput   < StandardError; end

    def self.call(header_attrs:, lines:, actor: nil)
      new(header_attrs: header_attrs, lines: lines, actor: actor).call
    end

    def initialize(header_attrs:, lines:, actor:)
      @header_attrs = header_attrs.to_h.with_indifferent_access
      @lines        = Array(lines).map { |l| l.to_h.with_indifferent_access }
      @actor        = actor
    end

    def call
      validate_header!
      validate_lines!
      from_warehouse = Warehouse.find(@header_attrs[:from_warehouse_id])
      to_warehouse   = Warehouse.find(@header_attrs[:to_warehouse_id])

      if from_warehouse.shopify_origin? || to_warehouse.shopify_origin?
        raise ReadOnlyOrigin, "Cannot transfer to or from a Shopify-managed warehouse"
      end

      StockTransfer.transaction do
        transfer = StockTransfer.create!(
          reference:          @header_attrs[:reference].presence || StockTransfer.next_reference,
          from_warehouse:     from_warehouse,
          to_warehouse:       to_warehouse,
          status:             "posted",
          reason:             (@header_attrs[:reason].presence || "transfer"),
          note:               @header_attrs[:note],
          posted_at:          Time.current,
          posted_by_user_id:  @actor&.id,
          created_by_user_id: @actor&.id
        )

        @lines.each do |raw|
          variant   = Variant.find(raw[:variant_id])
          quantity  = raw[:quantity].to_i

          line = transfer.stock_transfer_lines.create!(
            variant:  variant,
            quantity: quantity
          )

          from_si = StockItem.lock.find_by!(variant: variant, warehouse: from_warehouse)
          to_si   = StockItem.find_or_create_by!(variant: variant, warehouse: to_warehouse) do |si|
            si.quantity_on_hand = 0
          end
          to_si.lock!

          if from_si.shopify_origin? || to_si.shopify_origin?
            raise ReadOnlyOrigin, "Cannot transfer Shopify-managed stock items"
          end

          available = from_si.available
          if available < quantity
            raise InsufficientStock.new(
              "Insufficient stock for variant #{variant.id} at #{from_warehouse.code}: " \
              "requested #{quantity}, available #{available}",
              variant_id: variant.id, available: available, requested: quantity
            )
          end

          # StockMovement.reason is a strict enum; the header's business
          # reason is stored on the StockTransfer itself.
          Inventory::WriteMovement.call(
            stock_item: from_si,
            delta:      -quantity,
            reason:     "transfer",
            reference:  line,
            strict:     true
          )
          Inventory::WriteMovement.call(
            stock_item: to_si,
            delta:      quantity,
            reason:     "transfer",
            reference:  line,
            strict:     true
          )
        end

        transfer.reload
      end
    end

    private

    def validate_header!
      raise InvalidInput, "from_warehouse_id required" if @header_attrs[:from_warehouse_id].blank?
      raise InvalidInput, "to_warehouse_id required"   if @header_attrs[:to_warehouse_id].blank?
      if @header_attrs[:from_warehouse_id] == @header_attrs[:to_warehouse_id]
        raise InvalidInput, "from and to warehouse must differ"
      end
    end

    def validate_lines!
      raise InvalidInput, "at least one line is required" if @lines.empty?

      variant_ids = @lines.map { |l| l[:variant_id] }
      raise InvalidInput, "every line requires a variant_id" if variant_ids.any?(&:blank?)
      if variant_ids.uniq.size != variant_ids.size
        raise InvalidInput, "duplicate variant in lines"
      end

      @lines.each do |l|
        qty = l[:quantity].to_i
        raise InvalidInput, "quantity must be positive" if qty <= 0
      end
    end
  end
end
