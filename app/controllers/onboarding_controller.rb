# frozen_string_literal: true

class OnboardingController < ApplicationController
  skip_marketing_analytics
  before_action :require_login

  include Onboarding::AssistedPath

  before_action :ensure_sdk_selected, only: [ :install, :verify, :conversion ]

  def show
    redirect_to setup_path_destination if current_account.setup_path
  end

  def choose_path
    current_account.update!(setup_path: params[:setup_path])
    current_account.complete_onboarding_step!(:persona_selected)
    Lifecycle::Tracker.track("onboarding_setup_path_chosen", current_account, setup_path: current_account.setup_path)

    redirect_to setup_path_destination
  end

  def setup
    ensure_api_key_exists
    @plaintext_api_key = session[:plaintext_api_key]
    current_account.complete_onboarding_step!(:api_key_viewed)
  end

  def select_sdk
    current_account.update!(selected_sdk: params[:sdk])
    current_account.complete_onboarding_step!(:sdk_selected)
    Lifecycle::Tracker.track("onboarding_sdk_selected", current_account, sdk_key: current_account.selected_sdk)
    redirect_to sdk_onboarding_path
  end

  def waitlist_sdk
    SdkWaitlistSubmission.create!(
      email: current_user.email,
      sdk_key: waitlisted_sdk&.key,
      sdk_name: waitlisted_sdk&.display_name,
      account_id: current_account.prefix_id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
    redirect_to onboarding_setup_path, notice: "You've been added to the #{waitlisted_sdk&.display_name} waitlist. We'll notify you when it's ready!"
  end

  def regenerate_api_key
    # Revoke existing test keys
    current_account.api_keys.test.active.find_each(&:revoke!)

    # Generate new key
    result = ApiKeys::GenerationService.new(current_account, environment: :test).call
    session[:plaintext_api_key] = result[:plaintext_key] if result[:success]

    redirect_back fallback_location: onboarding_setup_path
  end

  def install
    @plaintext_api_key = session[:plaintext_api_key]
  end

  def verify
    redirect_to onboarding_conversion_path if first_event_completed?
  end

  def event_status
    current_account.complete_onboarding_step!(:first_event_received) if has_events? && !first_event_completed?

    render json: { received: has_events? }
  end

  def conversion
    redirect_to onboarding_attribution_path if first_conversion_completed?
  end

  def attribution
    current_account.complete_onboarding_step!(:attribution_viewed)
  end

  def complete
    redirect_to dashboard_path
  end

  def skip
    current_account.update!(onboarding_skipped_at: Time.current)
    Lifecycle::Tracker.track("onboarding_skipped", current_account, onboarding_percentage: current_account.onboarding_percentage, current_step: current_account.current_onboarding_step)
    redirect_to dashboard_path
  end

  private

  def ensure_sdk_selected
    redirect_to onboarding_setup_path unless current_account.selected_sdk.present?
  end

  def setup_path_destination
    case current_account.setup_path
    when SetupPaths::TEAMMATE then onboarding_invite_teammate_path
    when SetupPaths::ASSISTED then onboarding_discovery_path
    else onboarding_setup_path
    end
  end

  def first_event_completed?
    current_account.onboarding_step_completed?(:first_event_received)
  end

  def first_conversion_completed?
    current_account.onboarding_step_completed?(:first_conversion)
  end

  def has_events?
    current_account.events.exists?
  end

  def selected_sdk
    @selected_sdk ||= SdkRegistry.find(params[:sdk])
  end

  def sdk_onboarding_path
    onboarding_install_path
  end

  def waitlisted_sdk
    @waitlisted_sdk ||= SdkRegistry.find(params[:sdk])
  end

  def current_sdk
    @current_sdk ||= SdkRegistry.find(current_account.selected_sdk) || SdkRegistry.all.first
  end

  def test_api_key
    @test_api_key ||= current_account.api_keys.test.order(created_at: :desc).first
  end

  def plaintext_api_key
    session[:plaintext_api_key]
  end

  def available_sdks
    @available_sdks ||= SdkRegistry.for_onboarding
  end

  def latest_conversion
    @latest_conversion ||= current_account.conversions.order(created_at: :desc).first
  end

  def ensure_api_key_exists
    return if test_api_key.present?

    # Only generate if no key exists - plaintext comes from signup flow
    result = ApiKeys::GenerationService.new(current_account, environment: :test).call
    session[:plaintext_api_key] = result[:plaintext_key] if result[:success]
  end

  helper_method :current_sdk, :test_api_key, :plaintext_api_key, :available_sdks, :latest_conversion
end
