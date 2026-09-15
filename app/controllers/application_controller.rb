class ApplicationController < ActionController::Base
  include Authorization
  include BranchScopable

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!

  layout :resolve_layout

  private

  def resolve_layout
    devise_controller? ? "auth" : "application"
  end
end
