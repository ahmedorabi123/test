module Api
  module V1
    class RolesController < ApplicationController
      include Pundit::Authorization

      def index
        authorize Role
        roles = Role.includes(:permissions).all
        render json: {
          data: roles.map { |r|
            {
              id: r.id,
              name: r.name,
              description: r.description,
              permissions: r.permissions.map { |p| "#{p.resource}:#{p.action}" }
            }
          }
        }
      end

      def show
        @role = Role.find(params[:id])
        authorize @role
        render json: {
          data: {
            id:          @role.id,
            name:        @role.name,
            description: @role.description,
            permissions: @role.permissions.map { |p| "#{p.resource}:#{p.action}" }
          }
        }
      end
    end
  end
end
