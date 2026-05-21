# frozen_string_literal: true

# Helpers for the unified onboarding chrome (top bar + pip rail).
# Specified in lib/docs/DESIGN_SYSTEM.md §10, wireframed at
# lib/mockups/onboarding-chrome.html.
#
# The current pip is set by the controller (via a before_action that fills
# @onboarding_current_pip), not derived from action_name here -- keeps the
# helper testable as a pure function of (current_account, @current_pip).
module OnboardingChromeHelper
  Pip = Data.define(:key, :label, :state)
  # actionable: true  -> filled-indigo "do this next" link.
  # actionable: false -> light-indigo "we're working / wait for us" link
  # back into the relevant onboarding screen. Both states are clickable.
  ResumeStatus = Data.define(:label, :path, :actionable)

  BRANCH_LABELS = {
    SetupPaths::SELF_SERVE => "Self-serve setup",
    SetupPaths::TEAMMATE   => "Teammate setup",
    SetupPaths::ASSISTED   => "Guided Setup"
  }.freeze

  PIP_SEQUENCE = {
    SetupPaths::SELF_SERVE => %i[pick_path api_key install verify conversion done],
    SetupPaths::TEAMMATE   => %i[pick_path invite_sent teammate_installs done],
    SetupPaths::ASSISTED   => %i[pick_path discovery book_kickoff pay done]
  }.freeze

  # First pip carries the user's choice phrase, not a generic "Pick path".
  # Reads as the user's own story across the chrome.
  PIP_CHOICE_LABELS = {
    SetupPaths::SELF_SERVE => "I'll do it",
    SetupPaths::TEAMMATE   => "My teammate will",
    SetupPaths::ASSISTED   => "mbuzz will do it"
  }.freeze

  PIP_LABELS = {
    api_key: "API key",
    install: "Install",
    verify: "Verify event",
    conversion: "Conversion",
    invite_sent: "Invite sent",
    teammate_installs: "Teammate installs",
    discovery: "About",
    book_kickoff: "Book kickoff",
    pay: "Pay",
    done: "Done"
  }.freeze

  PIP_DOT_CLASSES = {
    done:     "bg-indigo-600 border-2 border-indigo-600",
    current:  "bg-indigo-600 border-2 border-indigo-600 ring-2 ring-white ring-offset-2 ring-offset-indigo-600",
    upcoming: "bg-white border-2 border-gray-300",
    locked:   "bg-white border-2 border-dashed border-gray-300"
  }.freeze

  def onboarding_branch_label
    BRANCH_LABELS[current_account&.setup_path]
  end

  def onboarding_current_pip
    @onboarding_current_pip
  end

  def onboarding_current_pip_label
    pip_label_for(onboarding_current_pip)
  end

  def onboarding_pips
    return [] if pip_sequence.blank? || onboarding_current_pip.nil?

    pip_sequence.map.with_index { |key, index| build_pip(key, index) }
  end

  # Pips marked :done can carry a back-navigation target. Today only the
  # path-reset (pick_path) is wired; other completed steps stay passive
  # markers until their back-nav gating is defined. Per DESIGN_SYSTEM
  # §3.10, branch-switching is only allowed before the user has committed
  # to the branch (no events, no teammate invite, no discovery answers).
  def onboarding_pip_link(pip)
    return nil unless pip.state == :done
    return nil if pip.key == :pick_path && branch_committed?

    case pip.key
    when :pick_path
      { path: onboarding_change_setup_path_path, method: :delete }
    end
  end

  def branch_committed?
    case current_account&.setup_path
    when SetupPaths::SELF_SERVE then current_account.events.exists?
    when SetupPaths::TEAMMATE   then current_account.account_memberships.where.not(role: :owner).exists?
    when SetupPaths::ASSISTED   then current_account.setup_profile_completed_at.present?
    else false
    end
  end

  def onboarding_pip_dot_classes(state)
    PIP_DOT_CLASSES.fetch(state)
  end

  # Resume-nav pill shown in the main app nav while onboarding is in
  # progress. Returns a ResumeStatus(label, path) or nil if there's no
  # pill to show (no path chosen, skipped, or fully complete). Path may
  # be nil for status-only states (e.g. assisted waiting for admin to
  # send a payment link).
  def onboarding_resume_status
    return nil if current_account.blank? || current_account.setup_path.blank? || current_account.onboarding_skipped?

    case current_account.setup_path
    when SetupPaths::SELF_SERVE then self_serve_resume_status
    when SetupPaths::TEAMMATE   then teammate_resume_status
    when SetupPaths::ASSISTED   then assisted_resume_status
    end
  end

  def onboarding_pip_connector_classes(previous_state)
    previous_state == :done ? "bg-indigo-600" : "bg-gray-300"
  end

  private

  def pip_sequence
    @pip_sequence ||= PIP_SEQUENCE[current_account&.setup_path]
  end

  def current_pip_index
    @current_pip_index ||= pip_sequence.index(onboarding_current_pip)
  end

  def build_pip(key, index)
    Pip.new(key: key, label: pip_label_for(key), state: pip_state(key, index))
  end

  def pip_label_for(key)
    return PIP_CHOICE_LABELS[current_account&.setup_path] if key == :pick_path

    PIP_LABELS[key]
  end

  def pip_state(key, index)
    return :locked if pip_locked?(key)
    return :upcoming if current_pip_index.nil?
    return :done if index < current_pip_index
    return :current if index == current_pip_index

    :upcoming
  end

  def pip_locked?(key)
    key == :pay && current_account&.assisted? && payment_unreachable?
  end

  def payment_unreachable?
    guided_setup = current_account.guided_setup
    return true if guided_setup.nil?

    !(guided_setup.payment_token_active? || guided_setup.in_progress? || guided_setup.delivered?)
  end

  def self_serve_resume_status
    return nil if current_account.onboarding_step_completed?(:attribution_viewed)

    ResumeStatus.new(label: "Finish setup", path: self_serve_resume_path, actionable: true)
  end

  def self_serve_resume_path
    return onboarding_setup_path      unless current_account.onboarding_step_completed?(:sdk_selected)
    return onboarding_install_path    unless current_account.onboarding_step_completed?(:first_event_received)
    return onboarding_verify_path     unless current_account.onboarding_step_completed?(:first_event_received)
    return onboarding_conversion_path unless current_account.onboarding_step_completed?(:first_conversion)

    onboarding_attribution_path
  end

  def teammate_resume_status
    case teammate_resume_state
    when :invite_needed   then ResumeStatus.new(label: "Invite your teammate", path: onboarding_invite_teammate_path, actionable: true)
    when :awaiting_accept then ResumeStatus.new(label: "Awaiting your teammate", path: onboarding_invite_teammate_path, actionable: false)
    when :awaiting_event  then ResumeStatus.new(label: "Awaiting first event from your teammate", path: onboarding_invite_teammate_path, actionable: false)
    end
  end

  def teammate_resume_state
    invites = current_account.account_memberships.where.not(role: :owner)
    return :invite_needed   if invites.none?
    return :awaiting_accept if invites.where(status: :pending).exists?
    return nil              if current_account.events.exists?

    :awaiting_event
  end

  def assisted_resume_status
    case assisted_resume_state
    when :discovery_pending then ResumeStatus.new(label: "Finish setup", path: onboarding_install_service_path, actionable: true)
    when :booking_pending   then ResumeStatus.new(label: "Book your kickoff", path: onboarding_guided_setup_path, actionable: true)
    when :payment_ready     then ResumeStatus.new(label: "Pay for your setup", path: onboarding_payment_setup_path, actionable: true)
    when :paid_in_progress  then ResumeStatus.new(label: "Setup in progress", path: onboarding_payment_complete_path, actionable: false)
    when :awaiting_link     then ResumeStatus.new(label: "Kickoff booked — we'll be in touch", path: onboarding_guided_setup_path, actionable: false)
    end
  end

  def assisted_resume_state
    guided_setup = current_account.guided_setup
    return nil if guided_setup&.delivered?
    return :discovery_pending if current_account.setup_profile_completed_at.blank?
    return :booking_pending   if guided_setup.nil? || guided_setup.kickoff_booked_at.blank?
    return :payment_ready     if guided_setup.payment_token_active?
    return :paid_in_progress  if guided_setup.in_progress?

    :awaiting_link
  end
end
