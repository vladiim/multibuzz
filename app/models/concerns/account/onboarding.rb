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

  included do
    enum :onboarding_persona, { developer: 0, marketer: 1, both: 2 }
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

  private

  def just_activated?
    activated? && activated_at.nil?
  end

  def set_activation_timestamp!
    update!(activated_at: Time.current)
  end

  def set_completion_timestamp!
    update!(onboarding_completed_at: Time.current) if onboarding_completed_at.nil?
  end
end
