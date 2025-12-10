class OnboardingController < ApplicationController
  before_action :require_login
  before_action :ensure_sdk_selected, only: [:install, :verify, :conversion]

  def show
    redirect_to onboarding_setup_path if persona_selected?
  end

  def persona
    current_account.update!(onboarding_persona: params[:persona])
    current_account.complete_onboarding_step!(:persona_selected)

    redirect_to current_account.marketer? ? dashboard_path : onboarding_setup_path
  end

  def setup
    current_account.complete_onboarding_step!(:api_key_viewed)
  end

  def select_sdk
    if selected_sdk&.coming_soon?
      redirect_to onboarding_setup_path, alert: "#{selected_sdk.display_name} is coming soon. Join the waitlist for early access."
      return
    end

    current_account.update!(selected_sdk: params[:sdk])
    current_account.complete_onboarding_step!(:sdk_selected)
    redirect_to onboarding_install_path
  end

  def install
  end

  def verify
  end

  def event_status
    current_account.complete_onboarding_step!(:first_event_received) if has_events? && !first_event_completed?

    render json: { received: has_events? }
  end

  def conversion
  end

  def attribution
    current_account.complete_onboarding_step!(:attribution_viewed)
  end

  def complete
    redirect_to dashboard_path
  end

  private

  def ensure_sdk_selected
    redirect_to onboarding_setup_path unless current_account.selected_sdk.present?
  end

  def persona_selected?
    current_account.onboarding_step_completed?(:persona_selected)
  end

  def first_event_completed?
    current_account.onboarding_step_completed?(:first_event_received)
  end

  def has_events?
    current_account.events.exists?
  end

  def selected_sdk
    @selected_sdk ||= SdkRegistry.find(params[:sdk])
  end

  def current_sdk
    @current_sdk ||= SdkRegistry.find(current_account.selected_sdk)
  end

  def test_api_key
    @test_api_key ||= current_account.api_keys.test.first
  end

  def available_sdks
    @available_sdks ||= SdkRegistry.for_onboarding
  end

  def latest_conversion
    @latest_conversion ||= current_account.conversions.order(created_at: :desc).first
  end

  helper_method :current_sdk, :test_api_key, :available_sdks, :latest_conversion
end
