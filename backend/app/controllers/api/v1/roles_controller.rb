module Api
  module V1
    class RolesController < ApplicationController
      include Pundit::Authorization

      before_action :set_role, only: %i[show update destroy]

      def index
        authorize Role
        roles = Role.includes(:permissions)
        roles = apply_role_sort(roles)
        render json: { data: roles.map { |r| role_json(r) } }
      end

      def show
        authorize @role
        render json: { data: role_json(@role) }
      end

      def create
        authorize Role
        result = Iam::CreateRole.call(
          name:            params.dig(:role, :name),
          description:     params.dig(:role, :description),
          permission_keys: Array(params.dig(:role, :permissions))
        )
        if result.success?
          AuditLog.record(user: current_user, action: "role.created",
                          subject: result.role, request: request,
                          diff: { name: result.role.name, permissions: Array(params.dig(:role, :permissions)) })
          render json: { data: role_json(result.role) }, status: :created
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      def update
        authorize @role
        before_perms = @role.permissions.map { |p| "#{p.resource}:#{p.action}" }
        result = Iam::UpdateRole.call(
          role:            @role,
          name:            params.dig(:role, :name),
          description:     params.dig(:role, :description),
          permission_keys: params[:role]&.key?(:permissions) ? Array(params.dig(:role, :permissions)) : nil
        )
        if result.success?
          AuditLog.record(user: current_user, action: "role.updated",
                          subject: result.role, request: request,
                          diff: { before_permissions: before_perms,
                                  after_permissions: result.role.permissions.reload.map { |p| "#{p.resource}:#{p.action}" } })
          render json: { data: role_json(result.role) }
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      def destroy
        authorize @role
        if Role::SYSTEM_ROLES.include?(@role.name)
          return render json: { error: "Cannot delete system role '#{@role.name}'" }, status: :unprocessable_entity
        end
        if @role.users.exists?
          return render json: { error: "Cannot delete a role that is assigned to users" }, status: :unprocessable_entity
        end

        AuditLog.record(user: current_user, action: "role.deleted",
                        subject: @role, request: request,
                        diff: { name: @role.name })
        @role.destroy!
        render json: { message: "Role deleted" }
      end

      private

      ROLE_SORT_ALLOWLIST = %w[name created_at].freeze

      def apply_role_sort(scope)
        col = params[:sort].to_s.presence
        col = "name" unless ROLE_SORT_ALLOWLIST.include?(col)
        dir = params[:dir].to_s.downcase == "desc" ? :desc : :asc
        scope.order(col => dir)
      end

      def set_role
        @role = Role.find(params[:id])
      end

      def role_json(role)
        {
          id:          role.id,
          name:        role.name,
          description: role.description,
          system:      Role::SYSTEM_ROLES.include?(role.name),
          permissions: role.permissions.map { |p| "#{p.resource}:#{p.action}" }
        }
      end
    end
  end
end
