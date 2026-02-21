# frozen_string_literal: true

module Attribution
  class CrossDeviceCalculator
    include CreditEnrichment

    def initialize(conversion:, identity:, attribution_model:, conversion_paths: nil)
      @conversion = conversion
      @identity = identity
      @attribution_model = attribution_model
      @precomputed_conversion_paths = conversion_paths
    end

    def call
      return [] if touchpoints.empty?

      compute_credits
    end

    private

    attr_reader :conversion, :identity, :attribution_model, :precomputed_conversion_paths

    def touchpoints
      @touchpoints ||= journey_builder.call
    end

    def journey_builder
      @journey_builder ||= CrossDeviceJourneyBuilder.new(
        identity: identity,
        converted_at: conversion.converted_at,
        lookback_days: AttributionAlgorithms::DEFAULT_LOOKBACK_DAYS
      )
    end

    def conversion_paths
      @conversion_paths ||= precomputed_conversion_paths || Markov::ConversionPathsQuery.new(account).call
    end
  end
end
