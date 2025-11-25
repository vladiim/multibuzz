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
    # Note: visitor_id and session_id are now server-generated from cookies
    post api_v1_events_url,
      params: {
        events: [
          {
            event_type: "page_view",
            timestamp: Time.current.utc.iso8601,
            properties: {
              url: "https://example.com/products?utm_source=google&utm_medium=cpc&utm_campaign=integration_test&utm_content=ad_variant_a&utm_term=test+keywords",
              referrer: "https://google.com"
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

    # Then: Visitor is created (server-generated ID)
    visitor = account.visitors.last
    assert visitor.present?, "Visitor should be created"
    assert visitor.first_seen_at.present?
    assert visitor.last_seen_at.present?

    # And: Session is created with UTM data
    session = account.sessions.last
    assert session.present?, "Session should be created"
    assert_equal visitor.id, session.visitor_id
    assert_equal 1, session.page_view_count
    assert session.started_at.present?
    assert_nil session.ended_at

    # And: UTM parameters are captured from URL query string
    utm = session.initial_utm.with_indifferent_access
    assert_equal "google", utm[:utm_source]
    assert_equal "cpc", utm[:utm_medium]
    assert_equal "integration_test", utm[:utm_campaign]
    assert_equal "ad_variant_a", utm[:utm_content]
    assert_equal "test keywords", utm[:utm_term]

    # And: Event is created for this specific visitor/session
    event = account.events.where(
      visitor_id: visitor.id,
      session_id: session.id
    ).first
    assert event.present?, "Event should be created"
    assert event.occurred_at.present?

    # And: Event properties are stored
    assert_includes event.properties["url"], "example.com/products"
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

    initial_visitor_count_a = account_a.visitors.count
    initial_visitor_count_b = account_b.visitors.count

    # When: Account A creates an event
    post api_v1_events_url,
      params: {
        events: [
          {
            event_type: "page_view",
            timestamp: Time.current.utc.iso8601,
            properties: { url: "https://example.com/account-a-page" }
          }
        ]
      },
      headers: { "Authorization" => "Bearer #{api_key_a}" },
      as: :json

    assert_response :accepted
    perform_enqueued_jobs

    # Then: Account A has one more visitor
    assert_equal initial_visitor_count_a + 1, account_a.visitors.count,
      "Account A should have one more visitor"

    # And: Account B visitor count unchanged
    assert_equal initial_visitor_count_b, account_b.visitors.count,
      "Account B should not have new visitors"

    # And: Account B cannot see Account A's event by URL
    assert_equal 0, account_b.events.where(
      "properties->>'url' = ?", "https://example.com/account-a-page"
    ).count, "Account B should not have Account A's events"

    # And: Account A can see its own event
    assert account_a.events.where(
      "properties->>'url' = ?", "https://example.com/account-a-page"
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
    # Note: visitor_id/session_id are now server-generated, so use empty event_type to trigger failure
    post api_v1_events_url,
      params: {
        events: [
          {
            event_type: "page_view",
            timestamp: Time.current.utc.iso8601,
            properties: { url: "https://example.com" }
          },
          {
            event_type: "",  # Invalid - empty event type
            timestamp: Time.current.utc.iso8601,
            properties: { url: "https://example.com" }
          },
          {
            event_type: "page_view",
            timestamp: Time.current.utc.iso8601,
            properties: { url: "https://example.com/other" }
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
    assert_includes rejected["errors"].join, "event_type"
  end

  private

  def account
    @account ||= accounts(:one)
  end
end
