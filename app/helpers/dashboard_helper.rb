module DashboardHelper
  ATTRIBUTION_MODEL_DESCRIPTIONS = {
    "first_touch" => "100% credit to the first marketing touchpoint",
    "last_touch" => "100% credit to the last touchpoint before conversion",
    "linear" => "Equal credit distributed across all touchpoints",
    "time_decay" => "More credit to touchpoints closer to conversion",
    "u_shaped" => "40% to first, 40% to last, 20% split among middle",
    "w_shaped" => "30% first, 30% lead creation, 30% last, 10% middle",
    "participation" => "100% credit to every touchpoint (totals > 100%)"
  }.freeze

  def attribution_model_description(algorithm)
    ATTRIBUTION_MODEL_DESCRIPTIONS[algorithm.to_s] || "Custom attribution model"
  end
end
