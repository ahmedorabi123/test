module Api
  module V1
    class PermissionsController < ApplicationController
      include Pundit::Authorization

      def index
        authorize Permission
        render json: {
          data: Permission.order(:resource, :action).map { |p|
            { id: p.id, key: "#{p.resource}:#{p.action}", description: p.description }
          }
        }
      end
    end
  end
end
