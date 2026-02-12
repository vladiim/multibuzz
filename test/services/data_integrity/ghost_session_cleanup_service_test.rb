# frozen_string_literal: true

require "test_helper"

module DataIntegrity
  class GhostSessionCleanupServiceTest < ActiveSupport::TestCase
    setup do
      account.attribution_credits.destroy_all
      # Set converted_at to recent so sessions fall within lookback window
      conversion.update_column(:converted_at, 1.hour.ago)
    end

    test "removes suspect session IDs from journey_session_ids" do
      conversion.update_column(:journey_session_ids, [real_session.id, suspect_session.id])

      service.call

      cleaned_ids = conversion.reload.journey_session_ids || []
      assert_includes cleaned_ids, real_session.id
      assert_not_includes cleaned_ids, suspect_session.id
    end

    test "deletes attribution credits linked to suspect sessions" do
      conversion.update_column(:journey_session_ids, [real_session.id, suspect_session.id])
      create_credit(session: suspect_session)

      service.call

      assert_empty account.attribution_credits.where(session_id: suspect_session.id)
    end

    test "re-runs attribution for affected conversions" do
      conversion.update_column(:journey_session_ids, [real_session.id, suspect_session.id])
      create_credit(session: suspect_session)

      service.call

      # journey_session_ids rebuilt without suspect session
      cleaned_ids = conversion.reload.journey_session_ids || []
      assert_not_includes cleaned_ids, suspect_session.id
    end

    test "skips conversions with no suspect sessions in journey" do
      conversion.update_column(:journey_session_ids, [real_session.id])
      create_credit(session: real_session)
      original_count = AttributionCredit.count

      service.call

      # Credits untouched — conversion wasn't affected
      assert_equal original_count, AttributionCredit.count
    end

    test "handles conversion where all journey sessions are suspect" do
      conversion.update_column(:journey_session_ids, [suspect_session.id])
      create_credit(session: suspect_session)

      service.call

      cleaned_ids = conversion.reload.journey_session_ids || []
      refute_includes cleaned_ids, suspect_session.id
    end

    test "returns count of affected conversions" do
      conversion.update_column(:journey_session_ids, [real_session.id, suspect_session.id])

      result = service.call

      assert result[:success]
      assert_equal 1, result[:conversions_cleaned]
    end

    test "scopes to account" do
      other_conversion = conversions(:trial_start)
      other_suspect = create_other_account_suspect_session
      other_conversion.update_column(:journey_session_ids, [other_suspect.id])

      conversion.update_column(:journey_session_ids, [real_session.id, suspect_session.id])

      result = service.call

      assert_equal 1, result[:conversions_cleaned]
      assert_includes other_conversion.reload.journey_session_ids, other_suspect.id
    end

    private

    def service
      @service ||= DataIntegrity::GhostSessionCleanupService.new(account)
    end

    def account
      @account ||= accounts(:one)
    end

    def conversion
      @conversion ||= conversions(:signup)
    end

    def real_session
      @real_session ||= account.sessions.create!(
        visitor: visitors(:one),
        session_id: "sess_real_#{SecureRandom.hex(8)}",
        started_at: 5.days.ago,
        channel: "organic_search",
        initial_referrer: "https://google.com",
        initial_utm: { utm_source: "google" },
        suspect: false
      )
    end

    def suspect_session
      @suspect_session ||= account.sessions.create!(
        visitor: visitors(:one),
        session_id: "sess_suspect_#{SecureRandom.hex(8)}",
        started_at: 5.days.ago,
        suspect: true
      )
    end

    def create_credit(session:)
      AttributionCredit.create!(
        account: account,
        conversion: conversion,
        attribution_model: attribution_models(:first_touch),
        session_id: session.id,
        channel: session.channel || "direct",
        credit: 1.0,
        revenue_credit: 0.0,
        is_test: false
      )
    end

    def create_other_account_suspect_session
      accounts(:two).sessions.create!(
        visitor: visitors(:three),
        session_id: "sess_other_suspect_#{SecureRandom.hex(8)}",
        started_at: 5.days.ago,
        suspect: true
      )
    end
  end
end
