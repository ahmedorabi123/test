module Api
  module V1
    class UsersController < ApplicationController
      include Pundit::Authorization

      before_action :set_user, only: %i[show update destroy assign_role remove_role]

      def index
        authorize User
        @users = policy_scope(User).includes(:roles).order(:first_name)
        render json: { data: users_json(@users) }
      end

      def show
        authorize @user
        render json: { data: user_json(@user) }
      end

      def create
        authorize User
        @user = User.new(user_params)
        @user.password = SecureRandom.hex(16) if @user.password.blank?
        @user.save!
        AuditLog.record(user: current_user, action: "user.created",
                        subject: @user, request: request,
                        diff: { email: @user.email })
        render json: { data: user_json(@user) }, status: :created
      end

      def update
        authorize @user
        before = @user.attributes.slice("email", "first_name", "last_name", "active")
        @user.update!(user_update_params)
        AuditLog.record(user: current_user, action: "user.updated",
                        subject: @user, request: request,
                        diff: { before: before, after: @user.attributes.slice("email", "first_name", "last_name", "active") })
        render json: { data: user_json(@user) }
      end

      def destroy
        authorize @user
        @user.update!(active: false)
        AuditLog.record(user: current_user, action: "user.deactivated",
                        subject: @user, request: request)
        render json: { message: "User deactivated" }
      end

      def assign_role
        authorize @user, :update?
        role = Role.find(params[:role_id])
        @user.user_roles.find_or_create_by!(
          role: role,
          warehouse_id: params[:warehouse_id]
        )
        AuditLog.record(user: current_user, action: "user.role_assigned",
                        subject: @user, request: request,
                        diff: { role_id: role.id, role_name: role.name, warehouse_id: params[:warehouse_id] })
        render json: { data: user_json(@user.reload) }
      end

      def remove_role
        authorize @user, :update?
        role = Role.find(params[:role_id])
        @user.user_roles.where(role: role).destroy_all
        AuditLog.record(user: current_user, action: "user.role_removed",
                        subject: @user, request: request,
                        diff: { role_id: role.id, role_name: role.name })
        render json: { data: user_json(@user.reload) }
      end

      private

      def set_user
        @user = User.find(params[:id])
      end

      def user_params
        params.require(:user).permit(:email, :first_name, :last_name, :password)
      end

      def user_update_params
        params.require(:user).permit(:first_name, :last_name, :active)
      end

      def users_json(users)
        users.map { |u| user_json(u) }
      end

      def user_json(user)
        {
          id:          user.id,
          email:       user.email,
          first_name:  user.first_name,
          last_name:   user.last_name,
          active:      user.active,
          last_login_at: user.last_login_at,
          roles:       user.roles.map { |r| { id: r.id, name: r.name } }
        }
      end
    end
  end
end
