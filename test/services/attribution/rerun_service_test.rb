# frozen_string_literal: true

require "test_helper"

module Attribution
  class RerunServiceTest < ActiveSupport::TestCase
    test "processes stale conversions" do
      result = service.call

      assert result[:success], "Expected success but got: #{result.inspect}"
      assert_equal 1, result[:processed]
    end

    test "updates credit model version" do
      service.call

      credit = model.attribution_credits.first

      assert_equal model.version, credit.model_version
    end

    test "marks job completed" do
      service.call

      rerun_job.reload

      assert_predicate rerun_job, :completed?
      assert_predicate rerun_job.completed_at, :present?
    end

    test "updates processed count" do
      service.call

      rerun_job.reload

      assert_equal 1, rerun_job.processed_conversions
    end

    test "increments account reruns used" do
      initial_count = account.reruns_used_this_period

      service.call

      account.reload

      assert_equal initial_count + 1, account.reruns_used_this_period
    end

    test "marks job failed on error" do
      # Remove the algorithm to cause an error
      model.update_column(:algorithm, nil)

      service.call

      rerun_job.reload

      assert_predicate rerun_job, :failed?
      assert_predicate rerun_job.error_message, :present?
    end

    # --- Unattributed Conversions ---

    test "processes unattributed conversions (new model backfill)" do
      result = backfill_service.call

      assert result[:success], "Expected success but got: #{result.inspect}"
      assert_equal 1, result[:processed]
    end

    test "creates credits for unattributed conversions" do
      backfill_service.call

      assert_equal 1, backfill_model.attribution_credits.count
    end

    test "processes both stale and unattributed conversions" do
      mixed_service.call

      mixed_rerun_job.reload

      assert_equal 2, mixed_rerun_job.processed_conversions
    end

    private

    def service
      @service ||= Attribution::RerunService.new(rerun_job)
    end

    def rerun_job
      @rerun_job ||= create_rerun_job
    end

    def create_rerun_job
      create_stale_credit

      ::RerunJob.create!(
        account: account,
        attribution_model: model,
        total_conversions: 1,
        from_version: 1,
        to_version: model.version
      )
    end

    def model
      @model ||= begin
        m = account.attribution_models.create!(
          name: "Test Model",
          model_type: :custom,
          algorithm: :first_touch
        )
        m.update_columns(dsl_code: "test", version: 2)
        m.reload
      end
    end

    def create_stale_credit
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: model,
        session_id: session.id,
        channel: "direct",
        credit: 1.0,
        model_version: 1
      )
    end

    def conversion
      @conversion ||= account.conversions.create!(
        visitor: visitor,
        session_id: session.id,
        conversion_type: "test",
        converted_at: Time.current
      )
    end

    def identity
      @identity ||= account.identities.create!(
        external_id: "user-#{SecureRandom.hex(4)}",
        first_identified_at: Time.current,
        last_identified_at: Time.current
      )
    end

    def visitor
      @visitor ||= account.visitors.create!(
        visitor_id: "test-#{SecureRandom.hex(4)}",
        identity: identity
      )
    end

    def session
      @session ||= account.sessions.create!(
        visitor: visitor,
        session_id: "sess-#{SecureRandom.hex(4)}",
        started_at: 1.day.ago,
        channel: "direct"
      )
    end

    def account
      @account ||= Account.create!(
        name: "Stale Test Account",
        slug: "stale-test-#{SecureRandom.hex(4)}"
      )
    end

    # --- Backfill (unattributed) helpers ---

    def backfill_service
      @backfill_service ||= Attribution::RerunService.new(backfill_rerun_job)
    end

    def backfill_rerun_job
      @backfill_rerun_job ||= begin
        # Just create a conversion with no credits
        backfill_conversion

        ::RerunJob.create!(
          account: backfill_account,
          attribution_model: backfill_model,
          total_conversions: 1,
          from_version: 0,
          to_version: backfill_model.version
        )
      end
    end

    def backfill_model
      @backfill_model ||= backfill_account.attribution_models.create!(
        name: "Backfill Test Model",
        model_type: :custom,
        algorithm: :first_touch,
        dsl_code: "test"
      )
    end

    def backfill_account
      @backfill_account ||= Account.create!(
        name: "Backfill Test Account",
        slug: "backfill-test-#{SecureRandom.hex(4)}"
      )
    end

    def backfill_identity
      @backfill_identity ||= backfill_account.identities.create!(
        external_id: "backfill-user-#{SecureRandom.hex(4)}",
        first_identified_at: Time.current,
        last_identified_at: Time.current
      )
    end

    def backfill_visitor
      @backfill_visitor ||= backfill_account.visitors.create!(
        visitor_id: "backfill-visitor-#{SecureRandom.hex(4)}",
        identity: backfill_identity
      )
    end

    def backfill_session
      @backfill_session ||= backfill_account.sessions.create!(
        visitor: backfill_visitor,
        session_id: "backfill-sess-#{SecureRandom.hex(4)}",
        started_at: 1.day.ago,
        channel: "direct"
      )
    end

    def backfill_conversion
      @backfill_conversion ||= backfill_account.conversions.create!(
        visitor: backfill_visitor,
        session_id: backfill_session.id,
        conversion_type: "test",
        converted_at: Time.current
      )
    end

    # --- Mixed (stale + unattributed) helpers ---

    def mixed_service
      @mixed_service ||= Attribution::RerunService.new(mixed_rerun_job)
    end

    def mixed_rerun_job
      @mixed_rerun_job ||= begin
        # Create stale conversion
        mixed_account.attribution_credits.create!(
          conversion: mixed_stale_conversion,
          attribution_model: mixed_model,
          session_id: mixed_stale_session.id,
          channel: "direct",
          credit: 1.0,
          model_version: 1
        )

        # Create unattributed conversion (no credit)
        mixed_unattributed_conversion

        ::RerunJob.create!(
          account: mixed_account,
          attribution_model: mixed_model,
          total_conversions: 2,
          from_version: 1,
          to_version: mixed_model.version
        )
      end
    end

    def mixed_model
      @mixed_model ||= begin
        m = mixed_account.attribution_models.create!(
          name: "Mixed Test Model",
          model_type: :custom,
          algorithm: :first_touch
        )
        m.update_columns(dsl_code: "test", version: 2)
        m.reload
      end
    end

    def mixed_account
      @mixed_account ||= Account.create!(
        name: "Mixed Test Account",
        slug: "mixed-test-#{SecureRandom.hex(4)}"
      )
    end

    def mixed_identity
      @mixed_identity ||= mixed_account.identities.create!(
        external_id: "mixed-user-#{SecureRandom.hex(4)}",
        first_identified_at: Time.current,
        last_identified_at: Time.current
      )
    end

    def mixed_stale_visitor
      @mixed_stale_visitor ||= mixed_account.visitors.create!(
        visitor_id: "mixed-stale-visitor-#{SecureRandom.hex(4)}",
        identity: mixed_identity
      )
    end

    def mixed_unattributed_visitor
      @mixed_unattributed_visitor ||= mixed_account.visitors.create!(
        visitor_id: "mixed-unattr-visitor-#{SecureRandom.hex(4)}",
        identity: mixed_identity
      )
    end

    def mixed_stale_session
      @mixed_stale_session ||= mixed_account.sessions.create!(
        visitor: mixed_stale_visitor,
        session_id: "mixed-stale-sess-#{SecureRandom.hex(4)}",
        started_at: 1.day.ago,
        channel: "direct"
      )
    end

    def mixed_unattributed_session
      @mixed_unattributed_session ||= mixed_account.sessions.create!(
        visitor: mixed_unattributed_visitor,
        session_id: "mixed-unattr-sess-#{SecureRandom.hex(4)}",
        started_at: 1.day.ago,
        channel: "direct"
      )
    end

    def mixed_stale_conversion
      @mixed_stale_conversion ||= mixed_account.conversions.create!(
        visitor: mixed_stale_visitor,
        session_id: mixed_stale_session.id,
        conversion_type: "test",
        converted_at: Time.current
      )
    end

    def mixed_unattributed_conversion
      @mixed_unattributed_conversion ||= mixed_account.conversions.create!(
        visitor: mixed_unattributed_visitor,
        session_id: mixed_unattributed_session.id,
        conversion_type: "test",
        converted_at: Time.current
      )
    end
  end
end
