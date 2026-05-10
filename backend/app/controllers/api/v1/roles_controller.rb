module Api
  module V1
    class RolesController < ApplicationController
      include Pundit::Authorization

      before_action :set_role, only: %i[show update destroy]

      def index
        authorize Role
        roles = Role.includes(:permissions).order(:name)
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
          render json: { data: role_json(result.role) }, status: :created
        else
          render json: { error: result.error }, status: :unprocessable_entity
        end
      end

      def update
        authorize @role
        result = Iam::UpdateRole.call(
          role:            @role,
          name:            params.dig(:role, :name),
          description:     params.dig(:role, :description),
          permission_keys: params[:role]&.key?(:permissions) ? Array(params.dig(:role, :permissions)) : nil
        )
        if result.success?
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

        @role.destroy!
        render json: { message: "Role deleted" }
      end

      private

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
