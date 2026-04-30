class ApplicationController < ActionController::API
  include ActionController::HttpAuthentication::Token::ControllerMethods
  include Devise::Controllers::Helpers
  include Pundit::Authorization

  before_action :authenticate_user!
  before_action :set_request_id

  rescue_from ActiveRecord::RecordNotFound,    with: :not_found
  rescue_from ActiveRecord::RecordInvalid,     with: :unprocessable
  rescue_from Pundit::NotAuthorizedError,      with: :forbidden

  def ping
    render json: { status: "ok", user: current_user&.email }
  end

  private

  def set_request_id
    request_id = request.headers["X-Request-Id"].presence || SecureRandom.uuid
    response.headers["X-Request-Id"] = request_id
    Rails.logger.tagged(request_id) {} if Rails.logger.respond_to?(:tagged)
  end

  def not_found(exception)
    render_error(404, "not_found", exception.message)
  end

  def unprocessable(exception)
    render_error(422, "unprocessable_entity", exception.record.errors.full_messages.join(", "))
  end

  def forbidden
    render_error(403, "forbidden", "You are not authorized to perform this action")
  end

  def render_error(status, type, detail, code: nil)
    body = { status: status, type: type, detail: detail }
    body[:code] = code if code
    render json: { error: body }, status: status
  end
end
