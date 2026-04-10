# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include SetCurrentAttributes

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Marketing analytics opt-out: controllers handling secrets, credentials,
  # or visitor PII declare `skip_marketing_analytics` to suppress GTM/GA4/
  # Ads/Meta loading on their pages. The SensitivePaths deny-list is the
  # safety net for anything that slips through. The class_attribute is set
  # at class load time (when subclasses call skip_marketing_analytics), not
  # at request time, so it is thread-safe despite the rubocop warning.
  class_attribute :marketing_analytics_skipped, default: false # rubocop:disable ThreadSafety/ClassAndModuleAttributes

  def self.skip_marketing_analytics
    self.marketing_analytics_skipped = true
  end

  helper_method :view_mode, :test_mode?, :clv_mode, :clv_mode?, :demo_mode?, :marketing_analytics_enabled?

  def marketing_analytics_enabled?
    return false if self.class.marketing_analytics_skipped
    !SensitivePaths.match?(request.path)
  end

  VALID_VIEW_MODES = %w[production test].freeze
  DEFAULT_VIEW_MODE = "production"

  VALID_CLV_MODES = %w[transactions clv].freeze
  DEFAULT_CLV_MODE = "transactions"

  VALID_DEMO_MODES = %w[true false].freeze

  private

  # View mode toggle (like Stripe's test/live mode)
  # Defaults to test mode when onboarding is incomplete
  def view_mode
    return DEFAULT_VIEW_MODE unless current_user

    session[:view_mode].presence_in(VALID_VIEW_MODES) || default_view_mode
  end

  def default_view_mode
    return DEFAULT_VIEW_MODE unless current_account

    # Respect persistent live_mode_enabled setting
    current_account.live_mode_enabled? ? DEFAULT_VIEW_MODE : "test"
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

  # Demo mode - uses dummy data for screenshots and demos
  # Enable with ?demo=true query param
  def demo_mode?
    params[:demo] == "true"
  end
end
