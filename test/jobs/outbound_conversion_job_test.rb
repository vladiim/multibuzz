# frozen_string_literal: true

require "test_helper"

# Thin job. Per CLAUDE.md "Test the service, not the job." — this only
# verifies the job loads the records and invokes the service. Behaviour
# under each branch (delivered, skipped_no_credit, etc.) is covered by
# Conversions::OutboundDispatchServiceTest.
class OutboundConversionJobTest < ActiveJob::TestCase
  setup { Rails.cache.clear }

  test "loads records and produces a ConversionDispatch row" do
    stub_request(:post, %r{graph.facebook.com}).to_return(status: 200, body: "{}")

    OutboundConversionJob.perform_now(conversion.id, destination.id)

    assert ConversionDispatch.exists?(conversion: conversion, conversion_destination: destination)
  end

  test "retries on RetryableDispatchError raised by the dispatcher" do
    stub_request(:post, %r{graph.facebook.com}).to_return(status: 503, body: "{}")

    assert_enqueued_jobs(1, only: OutboundConversionJob) do
      OutboundConversionJob.perform_now(conversion.id, destination.id)
    end
  end

  test "does NOT retry on permanent 4xx (no exception raised)" do
    stub_request(:post, %r{graph.facebook.com}).to_return(
      status: 400, body: { error: { message: "Bad payload" } }.to_json
    )

    assert_no_enqueued_jobs(only: OutboundConversionJob) do
      OutboundConversionJob.perform_now(conversion.id, destination.id)
    end

    assert_equal ConversionDispatch::Statuses::FAILED_PERMANENT,
      ConversionDispatch.find_by!(conversion: conversion, conversion_destination: destination).status
  end

  private

  def account = @account ||= accounts(:one)
  def visitor = @visitor ||= visitors(:one)

  def destination
    @destination ||= ConversionDestination.create!(
      account: account, attribution_model: attribution_models(:last_touch),
      platform: "meta_capi", name: "Job Test",
      meta_pixel_id: "P_JOB", meta_access_token: "T_JOB", enabled: true
    )
  end

  def conversion
    @conversion ||= begin
      conv = account.conversions.create!(
        visitor: visitor, conversion_type: "Lead", converted_at: Time.current,
        idempotency_key: "job_#{SecureRandom.hex(4)}",
        identity: account.identities.create!(
          external_id: "u_job", first_identified_at: Time.current, last_identified_at: Time.current,
          email_sha256: Identities::Normaliser.sha256("user@example.com")
        )
      )
      session = account.sessions.create!(
        session_id: "sess_job_#{SecureRandom.hex(4)}", visitor: visitor,
        started_at: 1.hour.ago, last_activity_at: 1.hour.ago, click_ids: { "fbclid" => "AbC" }
      )
      AttributionCredit.create!(
        account: account, conversion: conv,
        attribution_model: attribution_models(:last_touch), session_id: session.id,
        channel: "paid_social", credit: 1.0
      )
      conv
    end
  end
end
