# frozen_string_literal: true

module Onboarding
  module AssistedPath
    extend ActiveSupport::Concern

    included do
      before_action :require_assisted_path, only: %i[discovery submit_discovery guided_setup accept_guided_setup confirmation submit_confirmation]
      before_action :require_completed_discovery, only: %i[guided_setup accept_guided_setup]
      before_action :require_teammate_path, only: %i[invite_teammate send_teammate_invite]

      helper_method :recommended_plan
    end

    def change_setup_path
      current_account.update!(setup_path: nil)
      redirect_to onboarding_path
    end

    def invite_teammate
      @invited_email = nil
      @invite_error = nil
    end

    def send_teammate_invite
      @invited_email = params[:email].to_s.strip
      invite_teammate_result[:success] ? deliver_teammate_invitation : (@invite_error = invite_teammate_result[:errors].first)
      render :invite_teammate
    end

    def discovery; end

    def submit_discovery
      current_account.update!(setup_profile: discovery_params, setup_profile_completed_at: Time.current)
      Lifecycle::Tracker.track("onboarding_discovery_completed", current_account)
      redirect_to onboarding_guided_setup_path
    end

    def guided_setup
      @plans = Plan.active.paid.sorted
      @recommended_plan = recommended_plan
    end

    def accept_guided_setup
      return redirect_with_alert("Choose a plan to continue.") if plan_slug.blank?

      ensure_pending_guided_setup
      accept_result[:success] ? redirect_to(accept_result[:checkout_url], allow_other_host: true) : redirect_with_alert(accept_result[:errors].first)
    end

    def confirmation
      @guided_setup = current_account.guided_setup
    end

    def submit_confirmation
      @guided_setup = current_account.guided_setup
      @scheduling_draft = scheduling_preferences_params

      if @scheduling_draft[SchedulingPreferences::TIMEZONE_KEY].blank?
        @scheduling_error = "Choose a time zone so we know when to reach you."
        render :confirmation, status: :unprocessable_entity
        return
      end

      @guided_setup&.update!(scheduling_preferences: @scheduling_draft)
      redirect_to dashboard_path
    end

    private

    def require_assisted_path
      redirect_to onboarding_path unless current_account.assisted?
    end

    def require_teammate_path
      redirect_to onboarding_path unless current_account.teammate?
    end

    def require_completed_discovery
      redirect_to onboarding_discovery_path unless current_account.setup_profile_completed?
    end

    def invite_teammate_result
      @invite_teammate_result ||= Team::InvitationService.new(
        account: current_account,
        inviter: current_user,
        email: params[:email],
        role: params[:role]
      ).call
    end

    def deliver_teammate_invitation
      TeamMailer.invitation(
        membership: invite_teammate_result[:membership],
        token: invite_teammate_result[:invitation_token]
      ).deliver_later
    end

    def recommended_plan
      @recommended_plan ||= Plan.recommended_for_ad_spend(current_account.setup_profile["monthly_ad_spend"])
    end

    def ensure_pending_guided_setup
      return current_guided_setup if current_guided_setup.present?

      current_account.create_guided_setup!(integration_target: GuidedSetup.integration_target_for(current_account.setup_profile))
    end

    def current_guided_setup
      @current_guided_setup ||= current_account.guided_setup
    end

    def accept_result
      @accept_result ||= Billing::CreditCheckoutService.new(
        account: current_account,
        plan_slug: plan_slug,
        urls: { success: onboarding_confirmation_url, cancel: onboarding_guided_setup_url }
      ).call
    end

    def plan_slug
      params[:plan_slug].to_s.presence
    end

    def redirect_with_alert(message)
      redirect_to onboarding_guided_setup_path, alert: message
    end

    def discovery_params
      params.require(:setup_profile).permit(
        :attribution_goal, :attribution_goal_other,
        :monthly_ad_spend, :monthly_ad_spend_other,
        :ad_platforms_other, :install_platforms_other,
        ad_platforms: [], install_platforms: []
      ).to_h
    end

    def scheduling_preferences_params
      raw = params.fetch(:scheduling_preferences, {})
      raw = raw.respond_to?(:to_unsafe_h) ? raw.to_unsafe_h : raw

      {
        SchedulingPreferences::TIMEZONE_KEY    => raw[:timezone].to_s.strip.presence,
        SchedulingPreferences::DAYS_KEY        => Array(raw[:days]).reject(&:blank?) & SchedulingPreferences::DAYS_OF_WEEK,
        SchedulingPreferences::TIME_BLOCKS_KEY => Array(raw[:time_blocks]).reject(&:blank?) & SchedulingPreferences::TIME_BLOCKS
      }.compact
    end
  end
end
