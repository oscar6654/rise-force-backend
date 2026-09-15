# Custom RBAC enforcement (mirrors vcsi_rise). Controllers call
#   authorize!(:store, :create)
# and views gate UI with
#   can?(:pricing, :publish)
module Authorization
  extend ActiveSupport::Concern

  included do
    rescue_from AuthorizationError, with: :handle_authorization_error
    helper_method :can?, :cannot? if respond_to?(:helper_method)
  end

  class AuthorizationError < StandardError
    attr_reader :resource, :action

    def initialize(resource, action)
      @resource = resource
      @action = action
      super("Access denied: you don't have permission to #{action} #{resource}")
    end
  end

  def authorize!(resource, action)
    unless current_user&.has_permission?(resource, action)
      raise AuthorizationError.new(resource, action)
    end
  end

  def can?(resource, action)
    current_user&.has_permission?(resource, action) || false
  end

  def cannot?(resource, action)
    !can?(resource, action)
  end

  def authorize_role!(role_name)
    return if current_user&.has_role?(role_name)

    raise AuthorizationError.new(role_name, "act as")
  end

  private

  def handle_authorization_error(exception)
    respond_to do |format|
      format.html { redirect_to(main_app.root_path, alert: exception.message) }
      format.json { render json: { error: exception.message }, status: :forbidden }
      format.any  { head :forbidden }
    end
  end
end
