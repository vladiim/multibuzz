# frozen_string_literal: true

module Attribution
  class DataReadinessChecker
    REQUIRED_CONVERSIONS = 500
    REQUIRED_CHANNELS = 5

    MODEL_CONFIGS = {
      markov_chain: {
        name: "Markov Chain",
        description: "Data-driven credit based on channel removal effects. Calculates how much each channel contributes by measuring the impact when it's removed from customer journeys."
      },
      shapley_value: {
        name: "Shapley Value",
        description: "Fair credit based on each channel's marginal contribution. Uses game theory to fairly distribute credit based on each channel's contribution across all possible combinations."
      }
    }.freeze

    def initialize(account)
      @account = account
    end

    def call
      MODEL_CONFIGS.keys.each_with_object({}) do |model, result|
        result[model] = build_model_status(model)
      end
    end

    private

    attr_reader :account

    def build_model_status(model)
      config = MODEL_CONFIGS[model]

      {
        ready: ready?,
        name: config[:name],
        description: config[:description],
        current_conversions: current_conversions,
        required_conversions: REQUIRED_CONVERSIONS,
        conversions_needed: conversions_needed,
        current_channels: current_channels,
        required_channels: REQUIRED_CHANNELS,
        channels_needed: channels_needed,
        progress_percent: progress_percent
      }
    end

    def ready?
      current_conversions >= REQUIRED_CONVERSIONS && current_channels >= REQUIRED_CHANNELS
    end

    def current_conversions
      @current_conversions ||= account.conversions.count
    end

    def conversions_needed
      [ REQUIRED_CONVERSIONS - current_conversions, 0 ].max
    end

    def current_channels
      @current_channels ||= unique_channels_from_conversions.count
    end

    def channels_needed
      [ REQUIRED_CHANNELS - current_channels, 0 ].max
    end

    def progress_percent
      return 100 if ready?

      conversion_progress = (current_conversions.to_f / REQUIRED_CONVERSIONS * 100).to_i
      [ conversion_progress, 100 ].min
    end

    def unique_channels_from_conversions
      account
        .sessions
        .joins("INNER JOIN conversions ON sessions.id = ANY(conversions.journey_session_ids)")
        .where(conversions: { account_id: account.id })
        .distinct
        .pluck(:channel)
        .compact
    end
  end
end
