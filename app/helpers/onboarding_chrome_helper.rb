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
    discovery: "Discovery",
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
  # markers until their back-nav gating is defined.
  def onboarding_pip_link(pip)
    return nil unless pip.state == :done

    case pip.key
    when :pick_path
      { path: onboarding_change_setup_path_path, method: :delete }
    end
  end

  def onboarding_pip_dot_classes(state)
    PIP_DOT_CLASSES.fetch(state)
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
end
