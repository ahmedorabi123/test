module Api
  module V1
    class PermissionsController < ApplicationController
      include Pundit::Authorization

      def index
        authorize Permission
        existing = Permission.all.index_by { |p| "#{p.resource}:#{p.action}" }
        keys = (Permission::ALL + existing.keys).uniq
        render json: {
          data: keys.sort.map { |key|
            resource, action = key.split(":", 2)
            p = existing[key]
            {
              id:          p&.id,
              key:         key,
              resource:    resource,
              action:      action,
              description: p&.description
            }
          }
        }
      end
    end
  end
end
