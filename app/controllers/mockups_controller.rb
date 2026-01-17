class MockupsController < ApplicationController
  before_action :require_admin_access

  layout "mockups/retro"

  def retro_homepage
  end

  def retro_demo
  end

  private

  def require_admin_access
    return if Rails.env.development?
    return if logged_in? && current_user&.admin?

    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
