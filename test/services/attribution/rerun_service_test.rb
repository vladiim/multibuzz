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
      assert rerun_job.completed?
      assert rerun_job.completed_at.present?
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
      assert rerun_job.failed?
      assert rerun_job.error_message.present?
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
      @account ||= accounts(:one)
    end
  end
end
