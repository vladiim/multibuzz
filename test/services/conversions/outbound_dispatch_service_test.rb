# frozen_string_literal: true

require "test_helper"

module Conversions
  class OutboundDispatchServiceTest < ActiveSupport::TestCase
    setup { Rails.cache.clear }

    test "calls the platform dispatcher and stamps attribution on a 2xx" do
      stub_request(:post, %r{graph.facebook.com}).to_return(status: 200, body: "{}")

      OutboundDispatchService.new(conversion, destination).call

      dispatch = ConversionDispatch.find_by!(conversion: conversion, conversion_destination: destination)

      assert_equal(
        [ ConversionDispatch::Statuses::DELIVERED, destination.attribution_model_id, 1.0 ],
        [ dispatch.status, dispatch.attribution_model_id, dispatch.platform_credit_share.to_f ]
      )
    end

    test "skipped_no_credit when platform credit share is below threshold" do
      destination.update!(minimum_credit_threshold: 0.5)
      AttributionCredit.where(conversion: conversion).destroy_all
      create_credit_for(meta_session, credit: 0.3)
      create_credit_for(organic_session, credit: 0.7)

      OutboundDispatchService.new(conversion, destination).call

      dispatch = ConversionDispatch.find_by!(conversion: conversion, conversion_destination: destination)

      assert_equal(
        [ ConversionDispatch::Statuses::SKIPPED_NO_CREDIT, 0.3 ],
        [ dispatch.status, dispatch.platform_credit_share.to_f ]
      )
    end

    test "skipped_no_credit when conversion has no attribution credits at all" do
      AttributionCredit.where(conversion: conversion).destroy_all

      OutboundDispatchService.new(conversion, destination).call

      assert_equal ConversionDispatch::Statuses::SKIPPED_NO_CREDIT,
        ConversionDispatch.find_by!(conversion: conversion, conversion_destination: destination).status
    end

    test "attribution stamped on the row even when the dispatcher raises a retryable error" do
      stub_request(:post, %r{graph.facebook.com}).to_return(
        status: 500, body: { error: { message: "Boom" } }.to_json
      )

      assert_raises(AdDestinations::Errors::RetryableDispatchError) do
        OutboundDispatchService.new(conversion, destination).call
      end

      dispatch = ConversionDispatch.find_by!(conversion: conversion, conversion_destination: destination)

      assert_equal(
        [ ConversionDispatch::Statuses::FAILED_TRANSIENT, destination.attribution_model_id, 1.0 ],
        [ dispatch.status, dispatch.attribution_model_id, dispatch.platform_credit_share.to_f ]
      )
    end

    test "platform_credit_share recorded even when status is delivered" do
      AttributionCredit.where(conversion: conversion).destroy_all
      create_credit_for(meta_session, credit: 0.5)
      create_credit_for(organic_session, credit: 0.5)
      stub_request(:post, %r{graph.facebook.com}).to_return(status: 200, body: "{}")

      OutboundDispatchService.new(conversion, destination).call

      dispatch = ConversionDispatch.find_by!(conversion: conversion, conversion_destination: destination)

      assert_predicate dispatch, :delivered?
      assert_in_delta 0.5, dispatch.platform_credit_share.to_f
    end

    private

    def account = @account ||= accounts(:one)
    def visitor = @visitor ||= visitors(:one)

    def destination
      @destination ||= ConversionDestination.create!(
        account: account, attribution_model: attribution_models(:last_touch),
        platform: "meta_capi", name: "Test",
        meta_pixel_id: "P", meta_access_token: "T", enabled: true,
        event_type_mapping: { "Lead" => { "meta_event" => "Lead" } }
      )
    end

    def conversion
      @conversion ||= begin
        conv = account.conversions.create!(
          visitor: visitor, conversion_type: "Lead", converted_at: Time.current,
          idempotency_key: "ods_#{SecureRandom.hex(4)}",
          identity: account.identities.create!(
            external_id: "u_ods", first_identified_at: Time.current, last_identified_at: Time.current,
            email_sha256: Identities::Normaliser.sha256("user@example.com")
          )
        )
        create_credit_for(meta_session, credit: 1.0, conversion: conv)
        conv
      end
    end

    def meta_session
      @meta_session ||= account.sessions.create!(
        session_id: "sess_meta_#{SecureRandom.hex(4)}", visitor: visitor,
        started_at: 1.hour.ago, last_activity_at: 1.hour.ago, click_ids: { "fbclid" => "AbC" }
      )
    end

    def organic_session
      @organic_session ||= account.sessions.create!(
        session_id: "sess_org_#{SecureRandom.hex(4)}", visitor: visitor,
        started_at: 1.hour.ago, last_activity_at: 1.hour.ago, click_ids: {}
      )
    end

    def create_credit_for(session, credit:, conversion: nil)
      AttributionCredit.create!(
        account: account, conversion: conversion || self.conversion,
        attribution_model: attribution_models(:last_touch), session_id: session.id,
        channel: "paid_social", credit: credit
      )
    end
  end
end
