# frozen_string_literal: true

module ScoreHelper
  LEVEL_COLORS = {
    1 => "var(--red)",
    2 => "var(--accent)",
    3 => "#a78bfa",
    4 => "var(--green)"
  }.freeze

  LEVEL_BGS = {
    1 => "rgba(255, 77, 106, 0.12)",
    2 => "rgba(77, 127, 255, 0.12)",
    3 => "rgba(167, 139, 250, 0.12)",
    4 => "rgba(77, 255, 145, 0.12)"
  }.freeze

  LEVEL_INSIGHTS = {
    1 => "You're relying on platform-reported data. Every channel is grading its own homework. The good news: the biggest ROI gain is moving from Level 1 to Level 2.",
    2 => "You've built a unified view and started questioning the numbers. That puts you ahead of most marketing teams. Next step: start cross-validating with a second method.",
    3 => "You're triangulating across methods. That's rare and valuable. The gap to close: structured experimentation to prove what's actually working.",
    4 => "You can prove causation and predict outcomes. Very few companies get here. Measurement is a competitive advantage, not just a reporting function."
  }.freeze

  def level_color(level)
    LEVEL_COLORS.fetch(level, LEVEL_COLORS[1])
  end

  def level_bg(level)
    LEVEL_BGS.fetch(level, LEVEL_BGS[1])
  end

  def level_insight(level)
    LEVEL_INSIGHTS.fetch(level, LEVEL_INSIGHTS[1])
  end
end
