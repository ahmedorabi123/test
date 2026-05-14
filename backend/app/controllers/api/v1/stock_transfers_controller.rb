module Api
  module V1
    class StockTransfersController < ApplicationController
      include Pundit::Authorization

      # GET /api/v1/stock_transfers
      def index
        authorize StockTransfer
        scope = policy_scope(StockTransfer)
                  .includes(:from_warehouse, :to_warehouse, :stock_transfer_lines)
                  .recent

        scope = scope.where(from_warehouse_id: params[:from_warehouse_id]) if params[:from_warehouse_id].present?
        scope = scope.where(to_warehouse_id:   params[:to_warehouse_id])   if params[:to_warehouse_id].present?
        scope = scope.where(status: params[:status])                       if params[:status].present?

        page     = params[:page].to_i.positive?     ? params[:page].to_i     : 1
        per_page = params[:per_page].to_i.positive? ? params[:per_page].to_i : 25

        total = scope.count
        items = scope.offset((page - 1) * per_page).limit(per_page)

        render json: {
          data: items.map { |t| StockTransferSerializer.call(t, include_lines: true) },
          meta: { page: page, per_page: per_page, total: total }
        }
      end

      # GET /api/v1/stock_transfers/:id
      def show
        authorize StockTransfer
        transfer = StockTransfer.includes(:from_warehouse, :to_warehouse, stock_transfer_lines: { variant: :product }).find(params[:id])
        render json: { data: StockTransferSerializer.call(transfer, include_lines: true, include_movements: true) }
      end

      # POST /api/v1/stock_transfers
      #
      # Multi-variant batch transfer. Accepts either the new batch payload:
      #
      #   { stock_transfer: { from_warehouse_id:, to_warehouse_id:, reason:, note: },
      #     lines: [{ variant_id:, quantity: }, ...] }
      #
      # or the legacy single-variant payload (`variant_id, from_warehouse_id,
      # to_warehouse_id, quantity`) which is normalised into a one-line batch.
      def create
        authorize StockTransfer
        header, lines = extract_payload

        transfer = Inventory::PostStockTransfer.call(
          header_attrs: header,
          lines:        lines,
          actor:        current_user
        )

        AuditLog.record(
          user:    current_user,
          action:  "inventory.transfer.posted",
          subject: transfer,
          diff: {
            reference:           transfer.reference,
            from_warehouse_code: transfer.from_warehouse.code,
            to_warehouse_code:   transfer.to_warehouse.code,
            line_count:          transfer.stock_transfer_lines.size,
            total_quantity:      transfer.total_quantity,
            reason:              transfer.reason
          },
          request: request
        )

        render json: { data: StockTransferSerializer.call(transfer, include_lines: true, include_movements: true) },
               status: :created
      rescue Inventory::PostStockTransfer::ReadOnlyOrigin => e
        render_error(423, "read_only_shopify_resource", e.message)
      rescue Inventory::PostStockTransfer::InsufficientStock => e
        render_error(422, "insufficient_stock", e.message,
                     code: { variant_id: e.variant_id, available: e.available, requested: e.requested })
      rescue Inventory::PostStockTransfer::InvalidInput, ActiveRecord::RecordInvalid => e
        render_error(422, "validation", e.message)
      rescue ActiveRecord::RecordNotFound => e
        render_error(404, "not_found", e.message)
      end

      private

      def extract_payload
        # New batch payload requires +lines+. Anything else is treated as the
        # legacy single-variant payload (Rails `wrap_parameters` may wrap it
        # under :stock_transfer, so we don't use that as the trigger).
        if params[:lines].present?
          header = (params[:stock_transfer] || {}).permit(
            :from_warehouse_id, :to_warehouse_id, :reason, :note, :reference
          ).to_h
          raw_lines = Array(params[:lines]).map do |l|
            line = l.is_a?(ActionController::Parameters) ? l : ActionController::Parameters.new(l.to_h)
            line.permit(:variant_id, :quantity).to_h
          end
          [header, raw_lines]
        else
          # Legacy single-variant payload. wrap_parameters may produce a
          # stock_transfer wrapper without +variant_id+ (not a column on the
          # header), so fall back to top-level params for any missing key.
          src = params[:stock_transfer] || ActionController::Parameters.new
          [
            {
              from_warehouse_id: src[:from_warehouse_id].presence || params[:from_warehouse_id],
              to_warehouse_id:   src[:to_warehouse_id].presence   || params[:to_warehouse_id],
              reason:            (src[:reason].presence || params[:reason].presence || "transfer")
            },
            [{
              variant_id: src[:variant_id].presence || params[:variant_id],
              quantity:   (src[:quantity].presence || params[:quantity]).to_i
            }]
          ]
        end
      end
    end
  end
end
