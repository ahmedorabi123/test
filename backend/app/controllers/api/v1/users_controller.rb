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
        render json: { data: user_json(@user) }, status: :created
      end

      def update
        authorize @user
        @user.update!(user_update_params)
        render json: { data: user_json(@user) }
      end

      def destroy
        authorize @user
        @user.update!(active: false)
        render json: { message: "User deactivated" }
      end

      def assign_role
        authorize @user, :update?
        role = Role.find(params[:role_id])
        @user.user_roles.find_or_create_by!(
          role: role,
          warehouse_id: params[:warehouse_id]
        )
        render json: { data: user_json(@user.reload) }
      end

      def remove_role
        authorize @user, :update?
        role = Role.find(params[:role_id])
        @user.user_roles.where(role: role).destroy_all
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
