module Api
  module V1
    module Auth
      # Bypasses Devise::SessionsController (incompatible with Rails 8 API-only mode).
      # Issues JWTs manually via Warden::JWTAuth.
      class SessionsController < ApplicationController
        skip_before_action :authenticate_user!, only: %i[create]

        # POST /api/v1/auth/login
        def create
          email = params.dig(:user, :email)&.downcase&.strip
          user  = User.find_by(email: email)

          unless user
            log_login_failure(email, "no_user")
            return render_error(401, "unauthorized", "No account found with that email address", code: "no_user")
          end

          unless user.valid_password?(params.dig(:user, :password))
            log_login_failure(email, "wrong_password", user: user)
            return render_error(401, "unauthorized", "Incorrect password", code: "wrong_password")
          end

          unless user.active?
            log_login_failure(email, "inactive", user: user)
            return render_error(403, "forbidden", "Your account has been deactivated", code: "inactive")
          end

          token, _payload = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
          user.update_column(:last_login_at, Time.current)

          render json: {
            data: {
              token: token,
              user: {
                id:          user.id,
                email:       user.email,
                first_name:  user.first_name,
                last_name:   user.last_name,
                roles:       user.roles.pluck(:name),
                permissions: user.permissions.pluck(:resource, :action).map { |r, a| "#{r}:#{a}" }
              }
            }
          }, status: :ok
        end

        # DELETE /api/v1/auth/logout
        def destroy
          # Revoke the JTI so this token can never be reused
          current_user.update_column(:jti, SecureRandom.uuid)
          render json: { message: "Logged out successfully" }, status: :ok
        end

        # GET /api/v1/auth/me
        def me
          render json: {
            data: {
              id:          current_user.id,
              email:       current_user.email,
              first_name:  current_user.first_name,
              last_name:   current_user.last_name,
              roles:       current_user.roles.pluck(:name),
              permissions: current_user.permissions.pluck(:resource, :action).map { |r, a| "#{r}:#{a}" }
            }
          }
        end

        private

        # Record every failed login so debugging auth issues is instant.
        # Never logs the password. Safe to call with nil user.
        def log_login_failure(email, reason, user: nil)
          Rails.logger.warn("[auth.login.failed] email=#{email.inspect} reason=#{reason}")
          AuditLog.create!(
            user_id:      user&.id,
            action:       "auth.login.failed",
            subject_type: "User",
            subject_id:   user&.id,
            diff:         { email: email, reason: reason },
            ip_address:   request.remote_ip,
            user_agent:   request.user_agent,
            occurred_at:  Time.current
          )
        rescue StandardError => e
          Rails.logger.error("[auth.login.failed] audit write failed: #{e.class}: #{e.message}")
        end
      end
    end
  end
end
