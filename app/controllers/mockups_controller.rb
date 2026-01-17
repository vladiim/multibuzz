class MockupsController < ApplicationController
  before_action :require_admin_access

  layout :choose_layout

  # V1 - Original retro mockups
  def retro_homepage
  end

  def retro_demo
  end

  # V2 - Enhanced retro with deeper 70s motifs
  def retrov2_homepage
  end

  def retrov2_demo
  end

  # V3 - Full analog depth: warmer avocado green, film grain, wavy patterns
  def retrov3_homepage
  end

  def retrov3_demo
  end

  private

  def choose_layout
    if action_name.start_with?("retrov3")
      "mockups/retrov3"
    elsif action_name.start_with?("retrov2")
      "mockups/retrov2"
    else
      "mockups/retro"
    end
  end

  def require_admin_access
    return if Rails.env.development?
    return if logged_in? && current_user&.admin?

    render file: Rails.public_path.join("404.html"), status: :not_found, layout: false
  end
end
