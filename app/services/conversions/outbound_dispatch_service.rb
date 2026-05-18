# frozen_string_literal: true

# Runs one (conversion × destination) outbound conversion-feedback flow:
#
# 1. Compute platform credit share via Conversions::PlatformCreditCalculator
#    (credits come from AttributionCalculationJob; if they don't exist
#    yet, share is 0.0 → skipped_no_credit)
# 2. If share < destination.minimum_credit_threshold (or zero) →
#    record skipped_no_credit and return without calling the dispatcher
# 3. Otherwise, dispatch via AdDestinations::Registry.dispatcher_for,
#    then stamp attribution_model_id + platform_credit_share on the row
#    so admin diagnostics show why this dispatch fired
#
# Called by OutboundConversionJob (the thin queue wrapper). Pulled out
# of the job so logic is testable without ActiveJob ceremony, and the
# job stays a one-liner per CLAUDE.md "Jobs = Thin Wrappers".
#
# Attribution stamp (attribution_model_id + platform_credit_share) is
# written to the dispatch row BEFORE the dispatcher is invoked so the
# stamp survives a RetryableDispatchError raised by the dispatcher.
# Both writes target the same row (find_or_initialize_by on the unique
# (conversion, destination) index).
module Conversions
  class OutboundDispatchService
    def initialize(conversion, destination)
      @conversion = conversion
      @destination = destination
    end

    def call
      return record_skipped_no_credit if credit_below_threshold?

      stamp_attribution
      dispatch_via_registry
    end

    private

    attr_reader :conversion, :destination

    def credit_share
      @credit_share ||= Conversions::PlatformCreditCalculator.new(conversion, destination).call
    end

    def credit_below_threshold?
      credit_share.zero? || credit_share < destination.minimum_credit_threshold
    end

    def dispatch_via_registry
      AdDestinations::Registry.dispatcher_for(destination).call(conversion)
    end

    def record_skipped_no_credit
      dispatch_row.update!(skipped_no_credit_attributes)
      dispatch_row
    end

    def stamp_attribution
      dispatch_row.update!(attribution_attributes)
    end

    def dispatch_row
      @dispatch_row ||= ConversionDispatch.find_or_initialize_by(
        conversion: conversion, conversion_destination: destination
      ).tap { |row| row.account = conversion.account }
    end

    def skipped_no_credit_attributes
      attribution_attributes.merge(status: ConversionDispatch::Statuses::SKIPPED_NO_CREDIT)
    end

    def attribution_attributes
      {
        attribution_model_id: destination.attribution_model_id,
        platform_credit_share: credit_share
      }
    end
  end
end
