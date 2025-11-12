require "test_helper"

class EventTrackingFlowTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  def setup
    # Clear rate limit cache before each test
    Rails.cache.delete("rate_limit:account:#{account.id}")
  end

  test "complete event tracking flow from API to database" do
    # Given: An account with a valid API key
    result = ApiKeys::GenerationService
      .new(account, :test)
      .call(description: "Integration test key")

    assert result[:success]
    plaintext_key = result[:plaintext_key]

    # When: Sending a batch of events via API
    post api_v1_events_url,
      params: {
        events: [
          {
            event_type: "page_view",
            visitor_id: "integration_test_visitor",
            session_id: "integration_test_session",
            timestamp: Time.current.utc.iso8601,
            properties: {
              url: "https://example.com/products",
              referrer: "https://google.com",
              utm_source: "google",
              utm_medium: "cpc",
              utm_campaign: "integration_test",
              utm_content: "ad_variant_a",
              utm_term: "test keywords"
            }
          }
        ]
      },
      headers: { "Authorization" => "Bearer #{plaintext_key}" },
      as: :json

    # Then: API accepts the event
    assert_response :accepted
    assert_equal 1, response.parsed_body["accepted"]
    assert_empty response.parsed_body["rejected"]

    # And: Rate limit headers are present
    assert response.headers["X-RateLimit-Limit"]
    assert response.headers["X-RateLimit-Remaining"]
    assert response.headers["X-RateLimit-Reset"]

    # When: Processing the job
    perform_enqueued_jobs

    # Then: Visitor is created
    visitor = account.visitors.find_by(visitor_id: "integration_test_visitor")
    assert visitor.present?, "Visitor should be created"
    assert visitor.first_seen_at.present?
    assert visitor.last_seen_at.present?

    # And: Session is created with UTM data
    session = account.sessions.find_by(session_id: "integration_test_session")
    assert session.present?, "Session should be created"
    assert_equal visitor.id, session.visitor_id
    assert_equal 1, session.page_view_count
    assert session.started_at.present?
    assert_nil session.ended_at

    # And: UTM parameters are captured
    assert_equal "google", session.initial_utm["utm_source"]
    assert_equal "cpc", session.initial_utm["utm_medium"]
    assert_equal "integration_test", session.initial_utm["utm_campaign"]
    assert_equal "ad_variant_a", session.initial_utm["utm_content"]
    assert_equal "test keywords", session.initial_utm["utm_term"]

    # And: Event is created for this specific visitor/session
    event = account.events.where(
      visitor_id: visitor.id,
      session_id: session.id
    ).first
    assert event.present?, "Event should be created"
    assert event.occurred_at.present?

    # And: Event properties are stored
    assert_equal "https://example.com/products", event.properties["url"]
    assert_equal "https://google.com", event.properties["referrer"]
    assert_equal "google", event.properties["utm_source"]
  end

  test "multi-tenancy isolation - accounts cannot access each others data" do
    # Given: Two accounts with API keys
    account_a = accounts(:one)
    account_b = accounts(:two)

    result_a = ApiKeys::GenerationService.new(account_a, :test).call
    result_b = ApiKeys::GenerationService.new(account_b, :test).call

    api_key_a = result_a[:plaintext_key]
    api_key_b = result_b[:plaintext_key]

    # When: Account A creates an event
    post api_v1_events_url,
      params: {
        events: [
          {
            event_type: "page_view",
            visitor_id: "account_a_unique_visitor",
            session_id: "account_a_unique_session",
            timestamp: Time.current.utc.iso8601,
            properties: { url: "https://example.com/account-a-page" }
          }
        ]
      },
      headers: { "Authorization" => "Bearer #{api_key_a}" },
      as: :json

    assert_response :accepted
    perform_enqueued_jobs

    # Then: Account B cannot see Account A's data
    assert_nil account_b.visitors.find_by(visitor_id: "account_a_unique_visitor"),
      "Account B should not see Account A's visitor"
    assert_nil account_b.sessions.find_by(session_id: "account_a_unique_session"),
      "Account B should not see Account A's session"

    # Account B should not have any events for Account A's visitor
    assert_equal 0, account_b.events.where(
      properties: { url: "https://example.com/account-a-page" }
    ).count, "Account B should not have Account A's events"

    # And: Account A can see its own data
    assert account_a.visitors.find_by(visitor_id: "account_a_unique_visitor").present?,
      "Account A should see its own visitor"
    assert account_a.sessions.find_by(session_id: "account_a_unique_session").present?,
      "Account A should see its own session"
    assert account_a.events.where(
      properties: { url: "https://example.com/account-a-page" }
    ).exists?, "Account A should have its own events"
  end

  test "rate limiting headers present in response" do
    result = ApiKeys::GenerationService.new(account, :test).call
    plaintext_key = result[:plaintext_key]

    # When: Making a request
    post api_v1_events_url,
      params: {
        events: [
          {
            event_type: "page_view",
            visitor_id: "visitor_test",
            session_id: "session_test",
            timestamp: Time.current.utc.iso8601,
            properties: { url: "https://example.com" }
          }
        ]
      },
      headers: { "Authorization" => "Bearer #{plaintext_key}" },
      as: :json

    # Then: Response includes rate limit headers
    assert_response :accepted
    assert response.headers["X-RateLimit-Limit"].present?
    assert response.headers["X-RateLimit-Remaining"].present?
    assert response.headers["X-RateLimit-Reset"].present?

    # And: Rate limit info is valid
    assert_equal "1000", response.headers["X-RateLimit-Limit"]
    assert response.headers["X-RateLimit-Remaining"].to_i >= 0
  end

  test "batch processing with partial failures" do
    result = ApiKeys::GenerationService.new(account, :test).call
    plaintext_key = result[:plaintext_key]

    # When: Sending a batch with valid and invalid events
    post api_v1_events_url,
      params: {
        events: [
          {
            event_type: "page_view",
            visitor_id: "valid_visitor",
            session_id: "valid_session",
            timestamp: Time.current.utc.iso8601,
            properties: { url: "https://example.com" }
          },
          {
            event_type: "page_view",
            # Missing visitor_id
            session_id: "invalid_session",
            timestamp: Time.current.utc.iso8601,
            properties: { url: "https://example.com" }
          },
          {
            event_type: "page_view",
            visitor_id: "another_valid_visitor",
            session_id: "another_valid_session",
            timestamp: Time.current.utc.iso8601,
            properties: { url: "https://example.com" }
          }
        ]
      },
      headers: { "Authorization" => "Bearer #{plaintext_key}" },
      as: :json

    # Then: Valid events accepted, invalid rejected
    assert_response :accepted
    assert_equal 2, response.parsed_body["accepted"]
    assert_equal 1, response.parsed_body["rejected"].size

    rejected = response.parsed_body["rejected"].first
    assert_equal 1, rejected["index"]
    assert_includes rejected["errors"].join, "visitor_id"
  end

  private

  def account
    @account ||= accounts(:one)
  end
end
