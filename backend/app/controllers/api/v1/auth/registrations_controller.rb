module Api
  module V1
    module Auth
      # Admin-only user creation. Bypasses Devise::RegistrationsController
      # (incompatible with Rails 8 API-only mode).
      class RegistrationsController < ApplicationController
        before_action :require_admin!

        # POST /api/v1/auth/register
        def create
          user = User.new(user_params)
          if user.save
            render json: { data: { id: user.id, email: user.email } }, status: :created
          else
            render_error(422, "unprocessable_entity", user.errors.full_messages.join(", "))
          end
        end

        private

        def require_admin!
          render_error(403, "forbidden", "Only admins can create users") unless current_user.admin?
        end

        def user_params
          params.require(:user).permit(:email, :password, :password_confirmation, :first_name, :last_name)
        end
      end
    end
  end
end
