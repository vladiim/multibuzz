# frozen_string_literal: true

require "test_helper"

module Attribution
  class RerunInitiationServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper
    test "returns error when no pending conversions" do
      result = service.call

      assert_not result[:success]
      assert_includes result[:errors].first, "No pending conversions"
    end

    test "creates rerun job when stale conversions within limit" do
      create_stale_credit

      assert_difference "::RerunJob.count", 1 do
        result = service.call
        assert result[:success]
      end
    end

    test "sets correct from and to version" do
      create_stale_credit

      result = service.call

      job = result[:rerun_job]
      assert_equal 1, job.from_version
      assert_equal 2, job.to_version
    end

    test "requires confirmation when overage needed" do
      account.update!(reruns_used_this_period: account.rerun_limit)
      create_stale_credit

      result = service.call

      assert_not result[:success]
      assert result[:requires_confirmation]
      assert result[:overage][:overage].positive?
    end

    test "proceeds with overage when confirmed and has subscription" do
      account.update!(
        reruns_used_this_period: account.rerun_limit,
        billing_status: :active,
        stripe_subscription_id: "sub_123"
      )
      create_stale_credit

      result = service_with_confirmation.call

      assert result[:success]
      assert_equal 1, result[:overage][:blocks]
    end

    test "enqueues processing job" do
      create_stale_credit

      assert_enqueued_with(job: Attribution::RerunProcessingJob) do
        service.call
      end
    end

    # --- Backfill (unattributed conversions) ---

    test "creates rerun job when unattributed conversions exist (backfill)" do
      create_unattributed_conversion

      assert_difference "::RerunJob.count", 1 do
        result = service.call
        assert result[:success], "Expected success but got: #{result.inspect}"
      end
    end

    test "sets from_version to 0 for new model backfill" do
      create_unattributed_conversion

      result = service.call

      job = result[:rerun_job]
      assert_equal 0, job.from_version
      assert_equal 2, job.to_version
    end

    test "counts both stale and unattributed conversions" do
      create_stale_credit
      create_unattributed_conversion

      result = service.call

      job = result[:rerun_job]
      assert_equal 2, job.total_conversions
    end

    private

    def service
      @service ||= build_service
    end

    def service_with_confirmation
      Attribution::RerunInitiationService.new(
        attribution_model: model,
        confirm_overage: true
      )
    end

    def build_service
      Attribution::RerunInitiationService.new(attribution_model: model)
    end

    def model
      @model ||= begin
        m = account.attribution_models.create!(
          name: "Test Model",
          model_type: :custom
        )
        m.update_columns(dsl_code: "test", version: 2)
        m
      end
    end

    def create_stale_credit
      conversion = account.conversions.create!(
        visitor: visitor,
        session_id: session.id,
        conversion_type: "test",
        converted_at: Time.current
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: model,
        session_id: session.id,
        channel: "direct",
        credit: 1.0,
        model_version: 1
      )
    end

    def create_unattributed_conversion
      unattributed_visitor = account.visitors.create!(
        visitor_id: "unattributed-#{SecureRandom.hex(4)}",
        identity: identity
      )

      unattributed_session = account.sessions.create!(
        visitor: unattributed_visitor,
        session_id: "unattributed-sess-#{SecureRandom.hex(4)}",
        started_at: 1.day.ago,
        channel: "direct"
      )

      account.conversions.create!(
        visitor: unattributed_visitor,
        session_id: unattributed_session.id,
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
        started_at: Time.current,
        channel: "direct"
      )
    end

    def account
      @account ||= Account.create!(
        name: "Rerun Test Account",
        slug: "rerun-test-#{SecureRandom.hex(4)}"
      )
    end
  end
end
