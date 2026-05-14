module Api
  module V1
    class AuditLogsController < ApplicationController
      def index
        authorize :audit_log, :index?

        scope = AuditLog.all.includes(:user)
        scope = scope.where("action ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:action_type])}%") if params[:action_type].present?
        scope = scope.where("LOWER(subject_type) = LOWER(?)", params[:subject_type])                            if params[:subject_type].present?
        scope = scope.where(user_id: params[:user_id])                                                            if params[:user_id].present?
        if params[:q].present?
          like = "%#{ActiveRecord::Base.sanitize_sql_like(params[:q])}%"
          scope = scope.where("audit_logs.action ILIKE :q OR (audit_logs.diff)::text ILIKE :q", q: like)
        end
        if params[:actor_email].present?
          scope = scope.joins(:user).where("users.email ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(params[:actor_email])}%")
        end
        if params[:from_date].present?
          begin
            scope = scope.where("occurred_at >= ?", Time.zone.parse(params[:from_date].to_s).beginning_of_day)
          rescue ArgumentError
            # ignore unparseable input
          end
        end
        if params[:to_date].present?
          begin
            scope = scope.where("occurred_at <= ?", Time.zone.parse(params[:to_date].to_s).end_of_day)
          rescue ArgumentError
            # ignore unparseable input
          end
        end

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
