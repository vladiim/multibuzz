class ApplicationController < ActionController::Base
  include SetCurrentAttributes

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  after_action :track_page_view, if: :should_track_page_view?

  helper_method :view_mode, :test_mode?, :clv_mode, :clv_mode?

  VALID_VIEW_MODES = %w[production test].freeze
  DEFAULT_VIEW_MODE = "production"

  VALID_CLV_MODES = %w[transactions clv].freeze
  DEFAULT_CLV_MODE = "transactions"

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

  # CLV mode toggle (transactions vs customer lifetime value)
  def clv_mode
    return DEFAULT_CLV_MODE unless current_user

    session[:clv_mode].presence_in(VALID_CLV_MODES) || DEFAULT_CLV_MODE
  end

  def clv_mode?
    clv_mode == "clv"
  end

  # Dogfooding: Track page views
  def track_page_view
    Mbuzz.event("page_view", path: request.path)
  end

  def should_track_page_view?
    request.get? && response.successful? && !request.xhr?
  end
end
