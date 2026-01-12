require "test_helper"

class ConcurrentEventsDeduplicationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "concurrent events with same fingerprint deduplicate to single visitor" do
    # Given: An account with a valid test API key
    result = ApiKeys::GenerationService.new(account, environment: :test).call
    plaintext_key = result[:plaintext_key]

    # And: Visitor IDs and fingerprint setup
    visitor_id_1 = SecureRandom.hex(32)
    visitor_id_2 = SecureRandom.hex(32)

    # These represent concurrent requests from the same device/browser
    same_ip = "203.0.113.42"
    same_user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
    device_fingerprint = Digest::SHA256.hexdigest("#{same_ip}|#{same_user_agent}")[0, 32]
    timestamp = Time.current.utc.iso8601

    # Baseline - no visitors yet for this test
    initial_visitor_count = account.visitors.unscope(where: :is_test).test_data.count

    # Step 1: Create a session to establish visitor_1 (simulates first landing page)
    post api_v1_sessions_url,
      params: {
        session: {
          visitor_id: visitor_id_1,
          session_id: SecureRandom.hex(32),
          url: "https://example.com/landing?utm_source=google",
          started_at: timestamp,
          device_fingerprint: device_fingerprint
        }
      },
      headers: { "Authorization" => "Bearer #{plaintext_key}" },
      as: :json

    assert_response :accepted
    perform_enqueued_jobs

    # Step 2: First event request with visitor_id_1
    post api_v1_events_url,
      params: {
        events: [{
          event_type: "page_view",
          visitor_id: visitor_id_1,
          timestamp: timestamp,
          ip: same_ip,
          user_agent: same_user_agent,
          properties: { url: "https://example.com/page1" }
        }]
      },
      headers: { "Authorization" => "Bearer #{plaintext_key}" },
      as: :json

    assert_response :accepted
    perform_enqueued_jobs

    # Step 3: Concurrent request with DIFFERENT visitor_id but SAME fingerprint
    # This simulates a Turbo frame request that got a different cookie value
    post api_v1_events_url,
      params: {
        events: [{
          event_type: "page_view",
          visitor_id: visitor_id_2,  # Different visitor ID
          timestamp: timestamp,
          ip: same_ip,               # Same fingerprint
          user_agent: same_user_agent,
          properties: { url: "https://example.com/page2" }
        }]
      },
      headers: { "Authorization" => "Bearer #{plaintext_key}" },
      as: :json

    assert_response :accepted
    perform_enqueued_jobs

    # Then: Only ONE visitor should be created (deduplicated via fingerprint)
    new_visitors = account.visitors.unscope(where: :is_test).test_data.count - initial_visitor_count
    assert_equal 1, new_visitors,
      "Expected 1 visitor (deduplicated), got #{new_visitors}. Fingerprint dedup is not working!"

    # And: Both events should exist
    events = account.events.unscope(where: :is_test).test_data
      .where("occurred_at >= ?", 1.minute.ago)
      .where("properties->>'url' LIKE ?", "%example.com/page%")
    assert_equal 2, events.count, "Both events should be tracked"

    # And: Both events should reference the same visitor
    visitor_ids = events.pluck(:visitor_id).uniq
    assert_equal 1, visitor_ids.count, "Both events should belong to the same visitor"
  end

  test "events with different fingerprints are tracked separately" do
    # Given: An account with a valid test API key
    result = ApiKeys::GenerationService.new(account, environment: :test).call
    plaintext_key = result[:plaintext_key]

    # And: Two different visitors on different devices
    visitor_id_1 = SecureRandom.hex(32)
    visitor_id_2 = SecureRandom.hex(32)
    timestamp = Time.current.utc.iso8601

    initial_visitor_count = account.visitors.unscope(where: :is_test).test_data.count

    # Step 1: Create sessions for both visitors (different devices)
    # Device A
    post api_v1_sessions_url,
      params: {
        session: {
          visitor_id: visitor_id_1,
          session_id: SecureRandom.hex(32),
          url: "https://example.com/landing",
          started_at: timestamp
        }
      },
      headers: { "Authorization" => "Bearer #{plaintext_key}" },
      as: :json
    assert_response :accepted

    # Device B
    post api_v1_sessions_url,
      params: {
        session: {
          visitor_id: visitor_id_2,
          session_id: SecureRandom.hex(32),
          url: "https://example.com/landing",
          started_at: timestamp
        }
      },
      headers: { "Authorization" => "Bearer #{plaintext_key}" },
      as: :json
    assert_response :accepted

    # Then: TWO visitors should be created (different visitors)
    new_visitors = account.visitors.unscope(where: :is_test).test_data.count - initial_visitor_count
    assert_equal 2, new_visitors, "Expected 2 visitors (different devices)"

    # Step 2: Send events for each visitor
    post api_v1_events_url,
      params: {
        events: [{
          event_type: "page_view",
          visitor_id: visitor_id_1,
          timestamp: timestamp,
          ip: "203.0.113.10",
          user_agent: "Chrome/120",
          properties: { url: "https://example.com/page1" }
        }]
      },
      headers: { "Authorization" => "Bearer #{plaintext_key}" },
      as: :json

    assert_response :accepted
    assert_equal 1, response.parsed_body["accepted"]

    post api_v1_events_url,
      params: {
        events: [{
          event_type: "page_view",
          visitor_id: visitor_id_2,
          timestamp: timestamp,
          ip: "198.51.100.20",
          user_agent: "Safari/17",
          properties: { url: "https://example.com/page2" }
        }]
      },
      headers: { "Authorization" => "Bearer #{plaintext_key}" },
      as: :json

    assert_response :accepted
    assert_equal 1, response.parsed_body["accepted"]

    # And: Both events should have different visitors
    events = account.events.unscope(where: :is_test).test_data
      .where("occurred_at >= ?", 1.minute.ago)
      .where("properties->>'url' LIKE ?", "%example.com/page%")
    assert_equal 2, events.count, "Both events should be tracked"
    assert_equal 2, events.pluck(:visitor_id).uniq.count, "Events should belong to different visitors"
  end

  private

  def account
    @account ||= accounts(:one)
  end
end
