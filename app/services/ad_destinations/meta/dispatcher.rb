# frozen_string_literal: true

# Orchestrates a single (conversion × destination) Meta CAPI dispatch:
#
#   1. Resolve match keys via Conversions::MatchKeyResolver
#   2. If insufficient (no external_id, em, ph, fbc, or fbp), record
#      `skipped_no_identity` and return (no platform call wasted)
#   3. Build payload via PayloadBuilder
#   4. POST via ApiClient → Result
#   5. Map Result classification to ConversionDispatch status, persist
#
# Idempotent on retry: a previously-delivered dispatch is a no-op; a
# previously-failed dispatch updates the same row in place. Phase 6's
# OutboundConversionJob calls this dispatcher AFTER applying the
# attribution-model credit-share check (skipped_no_credit lives there,
# not here).
module AdDestinations
  module Meta
    class Dispatcher
      RESULT_STATUS_RULES = [
        [ :success?, ConversionDispatch::Statuses::DELIVERED ],
        [ :auth_failure?, ConversionDispatch::Statuses::TOKEN_FAILED ],
        [ :transient_failure?, ConversionDispatch::Statuses::FAILED_TRANSIENT ],
        [ :permanent_failure?, ConversionDispatch::Statuses::FAILED_PERMANENT ]
      ].freeze

      def initialize(conversion:, destination:)
        @conversion = conversion
        @destination = destination
      end

      def dispatch!
        return existing_delivered_dispatch if existing_delivered_dispatch
        return record_skipped_no_identity unless match_keys.meta_sufficient?

        record_api_result(api_client.post(payload))
      end

      private

      attr_reader :conversion, :destination

      def existing_delivered_dispatch
        dispatch_row.persisted? && dispatch_row.delivered? ? dispatch_row : nil
      end

      def dispatch_row
        @dispatch_row ||= ConversionDispatch.find_or_initialize_by(
          conversion: conversion, conversion_destination: destination
        ).tap { |row| row.account = conversion.account }
      end

      def match_keys
        @match_keys ||= Conversions::MatchKeyResolver.new(conversion).call
      end

      def payload
        @payload ||= PayloadBuilder.new(
          conversion: conversion, destination: destination, match_keys: match_keys
        ).call
      end

      def api_client
        @api_client ||= ApiClient.new(destination)
      end

      def record_skipped_no_identity
        dispatch_row.update!(status: ConversionDispatch::Statuses::SKIPPED_NO_IDENTITY)
        dispatch_row
      end

      def record_api_result(api_result)
        dispatch_row.assign_attributes(api_result_attributes(api_result))
        dispatch_row.save!
        dispatch_row
      end

      def api_result_attributes(api_result)
        {
          status: status_for(api_result),
          payload: payload,
          response: api_result.body,
          error: api_result.success? ? nil : api_result.error_message,
          fired_at: api_result.success? ? Time.current : nil,
          retries_count: api_result.success? ? dispatch_row.retries_count : dispatch_row.retries_count + 1
        }
      end

      def status_for(api_result)
        RESULT_STATUS_RULES.find { |predicate, _| api_result.public_send(predicate) }&.last
      end
    end
  end
end
