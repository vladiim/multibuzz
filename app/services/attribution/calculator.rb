# frozen_string_literal: true

module Attribution
  class Calculator
    CREDIT_PRECISION = 4
    CREDIT_TOLERANCE = 0.0001

    def initialize(conversion:, attribution_model:)
      @conversion = conversion
      @attribution_model = attribution_model
    end

    def call
      return [] if touchpoints.empty?

      normalize_credits(algorithm_credits)
        .map { |credit| enrich_with_session_data(credit) }
        .map { |credit| add_revenue_credit(credit) }
    end

    private

    attr_reader :conversion, :attribution_model

    def touchpoints
      @touchpoints ||= journey_builder.call
    end

    def journey_builder
      @journey_builder ||= JourneyBuilder.new(
        visitor: conversion.visitor,
        converted_at: conversion.converted_at,
        lookback_days: AttributionAlgorithms::DEFAULT_LOOKBACK_DAYS
      )
    end

    def algorithm_credits
      @algorithm_credits ||= algorithm.call
    end

    def normalize_credits(credits)
      return credits if credits.empty?

      credits
        .map { |c| c.merge(credit: c[:credit].round(CREDIT_PRECISION)) }
        .then { |rounded| ensure_sum_equals_one(rounded) }
    end

    def ensure_sum_equals_one(credits)
      diff = (1.0 - credits.sum { |c| c[:credit] }).round(CREDIT_PRECISION)

      return credits if diff.abs < CREDIT_TOLERANCE

      credits[0..-2] << credits.last.merge(credit: (credits.last[:credit] + diff).round(CREDIT_PRECISION))
    end

    def algorithm
      @algorithm ||= build_algorithm
    end

    def build_algorithm
      return build_probabilistic_model if probabilistic_model?

      attribution_model.algorithm_class.new(touchpoints)
    end

    def probabilistic_model?
      attribution_model.markov_chain? || attribution_model.shapley_value?
    end

    def build_probabilistic_model
      attribution_model.algorithm_class.new(
        touchpoints,
        conversion_paths: conversion_paths
      )
    end

    def conversion_paths
      @conversion_paths ||= Markov::ConversionPathsQuery.new(account).call
    end

    def account
      conversion.account
    end

    def enrich_with_session_data(credit)
      session = find_session(credit[:session_id])

      credit.merge(
        utm_source: utm_value(session, UtmKeys::SOURCE),
        utm_medium: utm_value(session, UtmKeys::MEDIUM),
        utm_campaign: utm_value(session, UtmKeys::CAMPAIGN)
      )
    end

    def find_session(session_id)
      sessions_map[session_id]
    end

    def sessions_map
      @sessions_map ||= begin
        session_ids = touchpoints.map { |t| t[:session_id] }
        account.sessions.where(id: session_ids).index_by(&:id)
      end
    end

    def utm_value(session, key)
      return nil unless session

      session.initial_utm&.dig(key) || session.initial_utm&.dig(key.to_sym)
    end

    def add_revenue_credit(credit)
      return credit unless conversion.revenue

      credit.merge(
        revenue_credit: (credit[:credit] * conversion.revenue).round(2)
      )
    end
  end
end
