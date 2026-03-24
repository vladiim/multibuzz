# frozen_string_literal: true

module SpendIntelligence
  class RecommendationService
    SCALE_THRESHOLD = 1.5
    REDUCE_THRESHOLD = 0.8
    SCALE_INCREMENT = 0.2
    REDUCE_DECREMENT = 0.15

    ACTIONS = {
      scale: "scale",
      maintain: "maintain",
      reduce: "reduce"
    }.freeze

    RATIONALES = {
      scale: "Still climbing the curve. Room to grow.",
      maintain: "Approaching saturation. Current spend is optimal.",
      reduce: "Past diminishing returns. Reallocate to higher-mROAS channels."
    }.freeze

    def self.recommend(channel:, roas:, marginal_roas:, current_spend:)
      new(
        channel: channel,
        roas: roas,
        marginal_roas: marginal_roas,
        current_spend: current_spend
      ).call
    end

    def initialize(channel:, roas:, marginal_roas:, current_spend:)
      @channel = channel
      @roas = roas
      @marginal_roas = marginal_roas
      @current_spend = current_spend
    end

    def call
      {
        channel: channel,
        action: action,
        roas: roas,
        marginal_roas: marginal_roas,
        change_amount: change_amount,
        rationale: rationale
      }
    end

    private

    attr_reader :channel, :roas, :marginal_roas, :current_spend

    def action
      return ACTIONS[:scale] if marginal_roas >= SCALE_THRESHOLD
      return ACTIONS[:reduce] if marginal_roas < REDUCE_THRESHOLD

      ACTIONS[:maintain]
    end

    def change_amount
      return (current_spend * SCALE_INCREMENT).round if action == ACTIONS[:scale]
      return -(current_spend * REDUCE_DECREMENT).round if action == ACTIONS[:reduce]

      0
    end

    def rationale = RATIONALES.fetch(action.to_sym)
  end
end
