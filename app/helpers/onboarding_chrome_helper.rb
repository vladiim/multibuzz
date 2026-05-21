# frozen_string_literal: true

# Helpers for the unified onboarding chrome (top bar + pip rail).
# Specified in lib/docs/DESIGN_SYSTEM.md §10, wireframed at
# lib/mockups/onboarding-chrome.html.
#
# Piece 1 wires the top bar only. Subsequent pieces (pip rail, per-screen
# current-pip resolution) will extend this file.
module OnboardingChromeHelper
  BRANCH_LABELS = {
    SetupPaths::SELF_SERVE => "Self-serve setup",
    SetupPaths::TEAMMATE   => "Teammate setup",
    SetupPaths::ASSISTED   => "Guided Setup"
  }.freeze

  def onboarding_branch_label
    BRANCH_LABELS[current_account&.setup_path]
  end
end
