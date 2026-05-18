# frozen_string_literal: true

require "test_helper"

module Conversions
  class DispatchServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup { Rails.cache.clear }

    test "enqueues OutboundConversionJob for each enabled destination matching the conversion type" do
      meta = build_destination(platform: "meta_capi", event_type_mapping: { "Lead" => { "meta_event" => "Lead" } })
      build_destination(platform: "meta_capi", name: "Other type", event_type_mapping: { "Purchase" => { "meta_event" => "Purchase" } })

      assert_enqueued_with(job: OutboundConversionJob, args: [ conversion.id, meta.id ]) do
        DispatchService.new(conversion).call
      end
    end

    test "skips disabled destinations" do
      build_destination(platform: "meta_capi", enabled: false, event_type_mapping: { "Lead" => { "meta_event" => "Lead" } })

      assert_no_enqueued_jobs(only: OutboundConversionJob) do
        DispatchService.new(conversion).call
      end
    end

    test "skips a destination that already has a delivered dispatch for this conversion" do
      destination = build_destination(platform: "meta_capi", event_type_mapping: { "Lead" => { "meta_event" => "Lead" } })
      ConversionDispatch.create!(
        conversion: conversion, conversion_destination: destination, account: account,
        status: ConversionDispatch::Statuses::DELIVERED, fired_at: 1.minute.ago
      )

      assert_no_enqueued_jobs(only: OutboundConversionJob) do
        DispatchService.new(conversion).call
      end
    end

    test "does nothing when account does not have CONVERSION_FEEDBACK feature flag" do
      build_destination(platform: "meta_capi", event_type_mapping: { "Lead" => { "meta_event" => "Lead" } })
      account.disable_feature!(FeatureFlags::CONVERSION_FEEDBACK)

      assert_no_enqueued_jobs(only: OutboundConversionJob) do
        DispatchService.new(conversion).call
      end
    end

    test "skips destinations whose event_type_mapping has no entry for this conversion's type" do
      build_destination(platform: "meta_capi", event_type_mapping: { "Purchase" => { "meta_event" => "Purchase" } })

      assert_no_enqueued_jobs(only: OutboundConversionJob) do
        DispatchService.new(conversion).call
      end
    end

    private

    def account
      @account ||= accounts(:one).tap { |a| a.enable_feature!(FeatureFlags::CONVERSION_FEEDBACK) }
    end

    def visitor
      @visitor ||= visitors(:one)
    end

    def conversion
      @conversion ||= account.conversions.create!(
        visitor: visitor, conversion_type: "Lead", converted_at: Time.current,
        idempotency_key: "ds_#{SecureRandom.hex(4)}"
      )
    end

    def build_destination(platform:, event_type_mapping:, enabled: true, name: nil)
      ConversionDestination.create!(
        account: account, attribution_model: attribution_models(:last_touch),
        platform: platform, name: name || "Test #{platform}",
        meta_pixel_id: "P", meta_access_token: "T",
        enabled: enabled, event_type_mapping: event_type_mapping
      )
    end
  end
end
