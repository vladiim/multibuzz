# frozen_string_literal: true

require_relative "../test_helper"
require "httparty"
require "concurrent"

# Tests for concurrent Turbo frame request deduplication
# This test simulates the scenario where multiple Turbo frames
# load simultaneously, each generating different random visitor_ids
# but the same deterministic session_id (based on IP + User-Agent fingerprint)
class TurboFrameDedupTest < Minitest::Test
  def setup
    @session_id = "sess_turbo_test_#{SecureRandom.hex(8)}"
    @device_fingerprint = "fp_turbo_#{SecureRandom.hex(16)}"
    @visitor_ids = 5.times.map { "vis_turbo_#{SecureRandom.hex(8)}" }
  end

  def teardown
    # Cleanup test data
    @visitor_ids.each do |vid|
      VerificationHelper.cleanup(visitor_id: vid)
    rescue StandardError
      nil
    end
  end

  # The main test case for Turbo frame deduplication
  # Simulates 5 concurrent requests (like 5 Turbo frames on one page)
  # Each with a DIFFERENT random visitor_id but SAME session_id
  # After the fix, all should resolve to the same canonical visitor
  def test_concurrent_turbo_frames_share_single_visitor
    skip "Requires local API server" unless api_available?

    # Simulate 5 concurrent Turbo frame requests
    # Each has different visitor_id but same session_id and fingerprint
    futures = @visitor_ids.map do |visitor_id|
      Concurrent::Future.execute do
        create_session(
          visitor_id: visitor_id,
          session_id: @session_id,
          device_fingerprint: @device_fingerprint,
          url: "https://example.com/turbo-page"
        )
      end
    end

    # Wait for all requests to complete
    results = futures.map(&:value)

    # At least 1 request should succeed
    success_count = results.count { |r| r.is_a?(Hash) && r["status"] == "accepted" }

    assert_operator success_count, :>=, 1, "At least 1 session request should succeed, got #{success_count}"

    # Wait for async processing
    sleep 2

    # Verify via API - count unique visitors for this session
    unique_visitors = count_unique_visitors_for_session(@session_id)

    # With the fix, all concurrent requests should use the SAME canonical visitor
    # Even if some requests fail, only 1 visitor should exist
    assert_equal 1, unique_visitors,
      "Expected 1 unique visitor for concurrent Turbo frames, got #{unique_visitors}. " \
      "The deduplication fix should prevent multiple visitors from being created."
  end

  # Test that different session_ids still create different visitors
  # (We shouldn't over-deduplicate)
  def test_different_sessions_create_different_visitors
    skip "Requires local API server" unless api_available?

    session_ids = 3.times.map { "sess_diff_#{SecureRandom.hex(8)}" }
    visitor_ids = 3.times.map { "vis_diff_#{SecureRandom.hex(8)}" }

    # Create 3 sessions with different session_ids (different users)
    session_ids.each_with_index do |session_id, i|
      result = create_session(
        visitor_id: visitor_ids[i],
        session_id: session_id,
        url: "https://example.com/page"
      )

      assert_equal "accepted", result["status"], "Session creation should succeed"
    end

    sleep 2

    # Each should have created a unique visitor
    unique_count = session_ids.each_with_index.sum do |sid, i|
      data = VerificationHelper.verify(visitor_id: visitor_ids[i])
      data && data[:sessions]&.any? { |s| s[:session_id] == sid } ? 1 : 0
    end

    assert_equal 3, unique_count,
      "Different session_ids should create different visitors"

    # Cleanup
    visitor_ids.each { |vid| VerificationHelper.cleanup(visitor_id: vid) rescue nil }
  end

  private

  def api_available?
    HTTParty.get("#{TestConfig.api_url}/health")
    true
  rescue StandardError
    false
  end

  def create_session(visitor_id:, session_id:, url:, referrer: nil, device_fingerprint: nil)
    HTTParty.post(
      "#{TestConfig.api_url}/sessions",
      headers: auth_headers,
      body: {
        session: {
          visitor_id: visitor_id,
          session_id: session_id,
          url: url,
          referrer: referrer,
          device_fingerprint: device_fingerprint,
          started_at: Time.now.utc.iso8601(6)
        }.compact
      }.to_json
    ).parsed_response
  rescue StandardError => e
    { "success" => false, "error" => e.message }
  end

  def count_unique_visitors_for_session(session_id)
    # Query through verification endpoint
    # First, check each of our test visitor_ids
    found_visitors = @visitor_ids.count do |vid|
      data = VerificationHelper.verify(visitor_id: vid)
      data && data[:sessions]&.any? { |s| s[:session_id] == session_id }
    end

    # If deduplication works, only 1 visitor should have this session
    found_visitors
  end

  def auth_headers
    {
      "Authorization" => "Bearer #{TestConfig.api_key}",
      "Content-Type" => "application/json"
    }
  end
end
