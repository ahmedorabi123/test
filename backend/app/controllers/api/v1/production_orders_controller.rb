module Api
  module V1
    class ProductionOrdersController < ApplicationController
      include Sortable

      sortable_by "number", "quantity", "status", "created_at",
                  default: { created_at: :desc }

      before_action :set_po, only: %i[show update destroy run cancel add_stage update_stage start_stage complete_stage destroy_stage]

      def index
        authorize ProductionOrder
        scope = ProductionOrder.includes(:parent_variant, :warehouse)
        scope = scope.where(status: params[:status])             if params[:status].present?
        scope = scope.where(warehouse_id: params[:warehouse_id]) if params[:warehouse_id].present?

        page     = [params[:page].to_i, 1].max
        per_page = (params[:per_page].to_i.positive? ? params[:per_page].to_i : 25).clamp(1, 200)
        records  = apply_sort(scope).offset((page - 1) * per_page).limit(per_page)

        render json: {
          data: records.map { |po| ProductionOrderSerializer.call(po) },
          meta: { page: page, per_page: per_page, total: scope.count }
        }
      end

      def show
        authorize @po
        render json: { data: ProductionOrderSerializer.call(@po) }
      end

      def create
        authorize ProductionOrder
        po = ProductionOrder.new(permitted_params.merge(created_by_id: current_user.id, status: "draft"))
        if po.save
          AuditLog.record(user: current_user, action: "production_order.create",
                          subject: po, request: request)
          render json: { data: ProductionOrderSerializer.call(po) }, status: :created
        else
          render json: { error: { type: "invalid", detail: po.errors.full_messages.join(", ") } }, status: :unprocessable_entity
        end
      end

      def update
        authorize @po
        if @po.update(permitted_params)
          render json: { data: ProductionOrderSerializer.call(@po) }
        else
          render json: { error: { type: "invalid", detail: @po.errors.full_messages.join(", ") } }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @po
        if %w[completed in_progress].include?(@po.status)
          return render json: { error: { type: "conflict", detail: "Cannot delete #{@po.status} production order" } }, status: :conflict
        end
        @po.destroy!
        head :no_content
      end

      def run
        authorize @po, :run?
        Manufacturing::ProductionRunner.call(@po)
        AuditLog.record(user: current_user, action: "production_order.run",
                        subject: @po, request: request,
                        diff: { quantity: @po.quantity, warehouse_id: @po.warehouse_id })
        render json: { data: ProductionOrderSerializer.call(@po) }
      rescue Manufacturing::ProductionRunner::Error => e
        render json: { error: { type: "conflict", detail: e.message } }, status: :conflict
      end

      def cancel
        authorize @po, :cancel?
        return render json: { error: { type: "conflict", detail: "Already completed" } }, status: :conflict if @po.status == "completed"
        @po.update!(status: "cancelled", cancelled_at: Time.current)
        render json: { data: ProductionOrderSerializer.call(@po) }
      end

      def add_stage
        authorize @po, :update?
        next_pos = (@po.production_stages.maximum(:position) || -1) + 1
        stage = @po.production_stages.create!(stage_params.merge(position: next_pos))
        @po.update!(production_mode: "staged") if @po.production_mode != "staged"
        render json: { data: ProductionStageSerializer.call(stage) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: { type: "invalid", detail: e.message } }, status: :unprocessable_entity
      end

      def update_stage
        authorize @po, :update?
        stage = @po.production_stages.find(params[:stage_id])
        stage.update!(stage_params)
        render json: { data: ProductionStageSerializer.call(stage) }
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: { type: "invalid", detail: e.message } }, status: :unprocessable_entity
      end

      def start_stage
        authorize @po, :update?
        stage = @po.production_stages.find(params[:stage_id])
        stage.start!
        render json: { data: ProductionStageSerializer.call(stage) }
      end

      def complete_stage
        authorize @po, :update?
        stage = @po.production_stages.find(params[:stage_id])
        stage.complete!
        render json: { data: ProductionStageSerializer.call(stage) }
      end

      def destroy_stage
        authorize @po, :update?
        stage = @po.production_stages.find(params[:stage_id])
        stage.destroy!
        head :no_content
      end

      private

      def set_po
        @po = ProductionOrder.find(params[:id])
      end

      def permitted_params
        params.require(:production_order).permit(:parent_variant_id, :warehouse_id, :quantity, :notes,
                                                  :production_mode, :unit_cost, :cost_currency)
      end

      def stage_params
        params.require(:stage).permit(:name, :status, :supplier_id, :unit_cost, :cost_currency, :notes, :position)
      end
    end
  end
end
