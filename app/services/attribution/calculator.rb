# frozen_string_literal: true

module Attribution
  class Calculator
    include CreditEnrichment

    CREDIT_PRECISION = 4
    CREDIT_TOLERANCE = 0.0001

    def initialize(conversion:, attribution_model:)
      @conversion = conversion
      @attribution_model = attribution_model
    end

    def call
      return [] if touchpoints.empty?

      normalize_credits(compute_credits)
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

    def conversion_paths
      @conversion_paths ||= Markov::ConversionPathsQuery.new(account).call
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
  end
end
