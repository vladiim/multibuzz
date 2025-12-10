class ApplicationController < ActionController::Base
  include SetCurrentAttributes

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  helper_method :view_mode, :test_mode?

  VALID_VIEW_MODES = %w[production test].freeze
  DEFAULT_VIEW_MODE = "production"

  private

  # View mode toggle (like Stripe's test/live mode)
  # Defaults to test mode when onboarding is incomplete
  def view_mode
    return DEFAULT_VIEW_MODE unless current_user

    session[:view_mode].presence_in(VALID_VIEW_MODES) || default_view_mode
  end

  def default_view_mode
    return DEFAULT_VIEW_MODE unless current_account

    current_account.onboarding_complete? ? DEFAULT_VIEW_MODE : "test"
  end

  def test_mode?
    view_mode == "test"
  end
end
