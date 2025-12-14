module AttributionHelper
  ATTRIBUTION_DESCRIPTIONS = {
    AttributionAlgorithms::FIRST_TOUCH => "100% credit goes to the first touchpoint that introduced the customer.",
    AttributionAlgorithms::LAST_TOUCH => "100% credit goes to the final touchpoint before conversion.",
    AttributionAlgorithms::LINEAR => "Credit is split equally across all touchpoints in the journey.",
    AttributionAlgorithms::TIME_DECAY => "More credit goes to touchpoints closer to conversion (7-day half-life).",
    AttributionAlgorithms::U_SHAPED => "40% to first touch, 40% to last touch, 20% split across middle touchpoints.",
    AttributionAlgorithms::PARTICIPATION => "100% credit to each unique channel (totals can exceed 100%)."
  }.freeze

  def attribution_model_description(model)
    ATTRIBUTION_DESCRIPTIONS[model] || "Custom attribution model."
  end
end
