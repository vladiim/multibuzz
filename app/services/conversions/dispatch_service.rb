# frozen_string_literal: true

# Finds the destinations a conversion should be uploaded to and
# enqueues an OutboundConversionJob per (conversion × destination).
# Called explicitly from Conversions::TrackingService once a conversion
# has been persisted (Phase 6.3) — not via an after_commit callback,
# per the codebase's "explicit global processor" pattern.
#
# Filtering rules:
# - Account must have CONVERSION_FEEDBACK feature flag enabled
# - Destination must be enabled = true
# - Destination's event_type_mapping must contain an entry for the
#   conversion's conversion_type
# - No `delivered` ConversionDispatch already exists for the
#   (conversion, destination) pair (idempotent re-enqueue is safe)
module Conversions
  class DispatchService
    def initialize(conversion)
      @conversion = conversion
    end

    def call
      return unless feature_enabled?

      eligible_destinations.each { |destination| enqueue(destination) }
    end

    private

    attr_reader :conversion

    def feature_enabled?
      conversion.account.feature_enabled?(FeatureFlags::CONVERSION_FEEDBACK)
    end

    def eligible_destinations
      enabled_destinations_for_conversion_type.reject { |destination| already_delivered?(destination) }
    end

    def enabled_destinations_for_conversion_type
      conversion.account.conversion_destinations.enabled.select do |destination|
        destination.event_type_mapping.key?(conversion.conversion_type)
      end
    end

    def already_delivered?(destination)
      ConversionDispatch.delivered.exists?(conversion: conversion, conversion_destination: destination)
    end

    def enqueue(destination)
      OutboundConversionJob.perform_later(conversion.id, destination.id)
    end
  end
end
