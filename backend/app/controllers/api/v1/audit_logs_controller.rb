module Api
  module V1
    class AuditLogsController < ApplicationController
      def index
        authorize :audit_log, :index?

        scope = AuditLog.all.includes(:user)
        scope = scope.where(action: params[:action_type])        if params[:action_type].present?
        scope = scope.where(subject_type: params[:subject_type]) if params[:subject_type].present?
        scope = scope.where(user_id: params[:user_id])           if params[:user_id].present?

        page     = [params[:page].to_i, 1].max
        per_page = (params[:per_page].to_i.positive? ? params[:per_page].to_i : 25).clamp(1, 200)
        records  = scope.order(occurred_at: :desc).offset((page - 1) * per_page).limit(per_page)

        render json: {
          data: records.map { |log| serialize(log) },
          meta: { page: page, per_page: per_page, total: scope.count }
        }
      end

      private

      def serialize(log)
        {
          id:           log.id,
          action:       log.action,
          subject_type: log.subject_type,
          subject_id:   log.subject_id,
          diff:         log.diff,
          ip_address:   log.ip_address,
          user_agent:   log.user_agent,
          occurred_at:  log.occurred_at,
          user:         log.user ? { id: log.user.id, email: log.user.email } : nil
        }
      end
    end
  end
end
