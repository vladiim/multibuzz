# frozen_string_literal: true

require "test_helper"

module AdDestinations
  module Meta
    class DispatcherTest < ActiveSupport::TestCase
      setup do
        Rails.cache.clear
      end

      test "delivered dispatch row is written when Meta returns 2xx" do
        stub_meta_response(status: 200, body: { events_received: 1, fbtrace_id: "X" })

        dispatch = Dispatcher.new(conversion: conversion, destination: destination).dispatch!

        assert_equal(
          [ ConversionDispatch::Statuses::DELIVERED, account.id, true, { "events_received" => 1, "fbtrace_id" => "X" } ],
          [ dispatch.status, dispatch.account_id, dispatch.fired_at.present?, dispatch.response ]
        )
      end

      test "stored payload matches what was built and POSTed" do
        stub_meta_response(status: 200, body: {})

        dispatch = Dispatcher.new(conversion: conversion, destination: destination).dispatch!
        payload = AdDestinations::Meta::PayloadBuilder.new(
          conversion: conversion, destination: destination, match_keys: Conversions::MatchKeyResolver.new(conversion).call
        ).call

        assert_equal payload.deep_stringify_keys, dispatch.payload
      end

      test "skipped_no_identity when match keys are insufficient" do
        identity_with_external_id_only.update!(email_sha256: nil)
        anonymous_conversion = create_conversion(identity: nil)

        dispatch = Dispatcher.new(conversion: anonymous_conversion, destination: destination).dispatch!

        assert_equal ConversionDispatch::Statuses::SKIPPED_NO_IDENTITY, dispatch.status
        refute_requested(:post, %r{graph.facebook.com})
      end

      test "no-op when a delivered dispatch already exists for (conversion, destination)" do
        ConversionDispatch.create!(
          conversion: conversion, conversion_destination: destination, account: account,
          status: ConversionDispatch::Statuses::DELIVERED, fired_at: 1.minute.ago
        )

        Dispatcher.new(conversion: conversion, destination: destination).dispatch!

        refute_requested(:post, %r{graph.facebook.com})
      end

      test "raises RetryableDispatchError on 401 and persists token_failed" do
        stub_meta_response(status: 401, body: { error: { type: "OAuthException", message: "Invalid OAuth token" } })

        assert_raises(AdDestinations::Errors::RetryableDispatchError) do
          Dispatcher.new(conversion: conversion, destination: destination).dispatch!
        end

        dispatch = ConversionDispatch.find_by!(conversion: conversion, conversion_destination: destination)

        assert_equal ConversionDispatch::Statuses::TOKEN_FAILED, dispatch.status
        assert_match(/Invalid OAuth token/, dispatch.error)
      end

      test "raises RetryableDispatchError on 429 and persists failed_transient" do
        stub_meta_response(status: 429, body: { error: { message: "Rate limit hit" } })

        assert_raises(AdDestinations::Errors::RetryableDispatchError) do
          Dispatcher.new(conversion: conversion, destination: destination).dispatch!
        end

        dispatch = ConversionDispatch.find_by!(conversion: conversion, conversion_destination: destination)

        assert_equal ConversionDispatch::Statuses::FAILED_TRANSIENT, dispatch.status
      end

      test "raises RetryableDispatchError on 5xx and persists failed_transient" do
        stub_meta_response(status: 503, body: { error: { message: "Service unavailable" } })

        assert_raises(AdDestinations::Errors::RetryableDispatchError) do
          Dispatcher.new(conversion: conversion, destination: destination).dispatch!
        end

        dispatch = ConversionDispatch.find_by!(conversion: conversion, conversion_destination: destination)

        assert_equal ConversionDispatch::Statuses::FAILED_TRANSIENT, dispatch.status
      end

      test "failed_permanent on 400 does NOT raise (no retry)" do
        stub_meta_response(status: 400, body: { error: { message: "Invalid event_name" } })

        dispatch = Dispatcher.new(conversion: conversion, destination: destination).dispatch!

        assert_equal ConversionDispatch::Statuses::FAILED_PERMANENT, dispatch.status
      end

      test "retry on a previously-failed dispatch updates the same row" do
        stub_meta_response(status: 500, body: { error: { message: "Boom" } })
        assert_raises(AdDestinations::Errors::RetryableDispatchError) do
          Dispatcher.new(conversion: conversion, destination: destination).dispatch!
        end
        first = ConversionDispatch.find_by!(conversion: conversion, conversion_destination: destination)

        stub_meta_response(status: 200, body: { events_received: 1 })
        second = Dispatcher.new(conversion: conversion, destination: destination).dispatch!

        assert_equal first.id, second.id, "should reuse the dispatch row, not duplicate"
        assert_predicate second.reload, :delivered?
      end

      private

      def account = @account ||= accounts(:one)
      def visitor = @visitor ||= visitors(:one)

      def conversion
        @conversion ||= create_conversion(identity: identity_with_external_id_only)
      end

      def identity_with_external_id_only
        @identity ||= account.identities.find_or_create_by!(external_id: "u_dispatcher_test") do |i|
          i.first_identified_at = Time.current
          i.last_identified_at = Time.current
          i.email_sha256 = Identities::Normaliser.sha256("user@example.com")
        end
      end

      def create_conversion(identity:)
        account.conversions.create!(
          visitor: visitor, identity: identity,
          conversion_type: "Lead", converted_at: Time.current,
          idempotency_key: "test_idem_#{SecureRandom.hex(4)}"
        )
      end

      def destination
        @destination ||= ConversionDestination.create!(
          account: account, attribution_model: attribution_models(:last_touch),
          platform: "meta_capi", name: "Test Meta",
          meta_pixel_id: "999_PIXEL", meta_access_token: "TEST_TOKEN", enabled: true
        )
      end

      def stub_meta_response(status:, body:)
        stub_request(:post, %r{#{Regexp.escape(Platforms::Meta::Capi::GRAPH_HOST)}/.+/events})
          .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
      end
    end
  end
end
