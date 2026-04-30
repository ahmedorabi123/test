# Base policy — deny by default unless the current user has the
# matching permission (resource:action) or is an admin.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    raise Pundit::NotAuthorizedError, "must be logged in" unless user

    @user   = user
    @record = record
  end

  # Override in subclasses to define the resource name
  def resource_name
    record.is_a?(Class) ? record.name.underscore.pluralize : record.class.name.underscore.pluralize
  end

  def index?   = admin_or_can?(:read)
  def show?    = admin_or_can?(:read)
  def create?  = admin_or_can?(:write)
  def update?  = admin_or_can?(:write)
  def destroy? = admin_or_can?(:delete)

  # Bulk + import/export use the same gates as index/create.
  def export?         = admin_or_can?(:read)
  def import?         = admin_or_can?(:write)
  def import_commit?  = admin_or_can?(:write)
  def bulk?           = admin_or_can?(:write)

  class Scope
    def initialize(user, scope)
      @user  = user
      @scope = scope
    end

    def resolve
      @scope.all
    end

    private
    attr_reader :user, :scope
  end

  private

  def admin_or_can?(action)
    user.admin? || user.can?(resource_name, action)
  end
end
