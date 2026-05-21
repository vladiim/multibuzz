# frozen_string_literal: true

module Account::Onboarding
  extend ActiveSupport::Concern

  ONBOARDING_STEPS = [
    :account_created,
    :persona_selected,
    :api_key_viewed,
    :sdk_selected,
    :first_event_received,
    :first_conversion,
    :attribution_viewed,
    :identity_linked,
    :onboarding_complete
  ].freeze

  # Discovery answers (assisted-path onboarding) live in setup_profile;
  # cap it like the other jsonb columns in the codebase.
  SETUP_PROFILE_MAX_BYTES = 50.kilobytes

  included do
    enum :onboarding_persona, { developer: 0, marketer: 1, both: 2 }
    enum :setup_path, SetupPaths::ENUM_VALUES
    validate :setup_profile_within_limits
  end

  def onboarding_step_completed?(step)
    step_index = ONBOARDING_STEPS.index(step)
    return false unless step_index

    (onboarding_progress & (1 << step_index)) != 0
  end

  def complete_onboarding_step!(step)
    step_index = ONBOARDING_STEPS.index(step)
    return unless step_index

    new_progress = onboarding_progress | (1 << step_index)
    update!(onboarding_progress: new_progress)

    set_activation_timestamp! if just_activated?
    set_completion_timestamp! if onboarding_complete?
  end

  def current_onboarding_step
    ONBOARDING_STEPS.find { |step| !onboarding_step_completed?(step) } || :onboarding_complete
  end

  def onboarding_percentage
    completed = ONBOARDING_STEPS.count { |step| onboarding_step_completed?(step) }
    ((completed.to_f / ONBOARDING_STEPS.size) * 100).round
  end

  def onboarding_complete?
    onboarding_step_completed?(:onboarding_complete)
  end

  def activated?
    onboarding_step_completed?(:first_conversion) &&
      onboarding_step_completed?(:attribution_viewed)
  end

  def onboarding_skipped?
    onboarding_skipped_at.present?
  end

  def should_show_onboarding_banner?
    return false if onboarding_complete?
    return false unless onboarding_skipped?

    !events.exists?
  end

  def resume_onboarding!
    update!(onboarding_skipped_at: nil)
  end

  def setup_profile_completed?
    setup_profile_completed_at.present?
  end

  private

  def setup_profile_within_limits
    return errors.add(:setup_profile, "must be a hash") unless setup_profile.is_a?(Hash)
    return if setup_profile.to_json.bytesize <= SETUP_PROFILE_MAX_BYTES

    errors.add(:setup_profile, "is too large")
  end

  def just_activated?
    activated? && activated_at.nil?
  end

  def set_activation_timestamp!
    update!(activated_at: Time.current)
    Lifecycle::Tracker.track("onboarding_activated", self)
  end

  def set_completion_timestamp!
    return unless onboarding_completed_at.nil?

    update!(onboarding_completed_at: Time.current)
    Lifecycle::Tracker.track("onboarding_completed", self, onboarding_percentage: onboarding_percentage)
  end
end
