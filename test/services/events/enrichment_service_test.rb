require "test_helper"

class Events::EnrichmentServiceTest < ActiveSupport::TestCase
  test "enriches event with HTTP metadata" do
    assert_equal event_type, result[:event_type]
    assert_equal url, result[:properties][:url]
    assert_equal "192.168.1.0", result[:properties][:request_metadata][:ip_address]
    assert_equal "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", result[:properties][:request_metadata][:user_agent]
    assert_equal "en-US,en;q=0.9", result[:properties][:request_metadata][:language]
    assert_equal "1", result[:properties][:request_metadata][:dnt]
  end

  test "anonymizes IP address by masking last octet" do
    @ip = "192.168.1.100"

    assert_equal "192.168.1.0", result[:properties][:request_metadata][:ip_address]
  end

  test "handles IPv6 address anonymization" do
    @ip = "2001:0db8:85a3:0000:0000:8a2e:0370:7334"

    assert_equal "2001:d00::", result[:properties][:request_metadata][:ip_address]
  end

  test "handles invalid IP address gracefully" do
    @ip = "not-an-ip"

    assert_nil result[:properties][:request_metadata][:ip_address]
  end

  test "merges request metadata with existing properties" do
    @properties = {
      custom_field: "custom_value",
      page_title: "Home"
    }

    assert_equal "custom_value", result[:properties][:custom_field]
    assert_equal "Home", result[:properties][:page_title]
    assert result[:properties][:request_metadata].present?
  end

  test "handles event_data with no properties" do
    @event_type = "signup"
    @properties = nil

    assert_equal "signup", result[:event_type]
    assert result[:properties][:request_metadata].present?
  end

  test "handles string keys in event_data" do
    @event_data = {
      "event_type" => "page_view",
      "properties" => { "url" => "https://example.com" }
    }

    assert_equal "page_view", result["event_type"]
    assert result[:properties][:request_metadata].present?
  end

  test "handles missing User-Agent header" do
    @user_agent = nil

    assert_nil result[:properties][:request_metadata][:user_agent]
  end

  test "handles missing Accept-Language header" do
    @accept_language = nil

    assert_nil result[:properties][:request_metadata][:language]
  end

  test "handles missing DNT header" do
    @dnt = nil

    assert_nil result[:properties][:request_metadata][:dnt]
  end

  test "preserves original event_data keys" do
    @event_type = "purchase"
    @timestamp = "2025-11-14T10:00:00Z"
    @properties = { amount: 99.99 }

    assert_equal "purchase", result[:event_type]
    assert_equal "2025-11-14T10:00:00Z", result[:timestamp]
    assert_equal 99.99, result[:properties][:amount]
  end

  test "extracts host from URL" do
    @properties = { url: "https://example.com/pricing" }

    assert_equal "example.com", result[:properties][:host]
  end

  test "extracts host with subdomain from URL" do
    @properties = { url: "https://app.example.com/dashboard" }

    assert_equal "app.example.com", result[:properties][:host]
  end

  test "extracts path from URL" do
    @properties = { url: "https://example.com/pricing" }

    assert_equal "/pricing", result[:properties][:path]
  end

  test "extracts path from URL with query params" do
    @properties = { url: "https://example.com/pricing?plan=pro" }

    assert_equal "/pricing", result[:properties][:path]
  end

  test "extracts path as root for domain-only URL" do
    @properties = { url: "https://example.com" }

    assert_equal "/", result[:properties][:path]
  end

  test "extracts query params as hash" do
    @properties = { url: "https://example.com/pricing?plan=pro&interval=monthly" }

    assert_equal({ "plan" => "pro", "interval" => "monthly" }, result[:properties][:query_params])
  end

  test "handles URL with UTM and non-UTM query params" do
    @properties = { url: "https://example.com/pricing?utm_source=google&plan=pro" }

    assert_equal({ "utm_source" => "google", "plan" => "pro" }, result[:properties][:query_params])
    assert_equal "google", result[:properties][:utm_source]
  end

  test "handles URL with no query params" do
    @properties = { url: "https://example.com/pricing" }

    assert_equal({}, result[:properties][:query_params])
  end

  test "handles URL with empty query string" do
    @properties = { url: "https://example.com/pricing?" }

    assert_equal({}, result[:properties][:query_params])
  end

  test "extracts referrer host" do
    @properties = { referrer: "https://google.com/search" }

    assert_equal "google.com", result[:properties][:referrer_host]
  end

  test "extracts referrer path" do
    @properties = { referrer: "https://google.com/search?q=analytics" }

    assert_equal "/search", result[:properties][:referrer_path]
  end

  test "handles empty referrer" do
    @properties = { referrer: "" }

    assert_nil result[:properties][:referrer_host]
    assert_nil result[:properties][:referrer_path]
  end

  test "handles missing referrer" do
    @properties = { url: "https://example.com" }

    assert_nil result[:properties][:referrer_host]
    assert_nil result[:properties][:referrer_path]
  end

  test "handles invalid URL gracefully" do
    @properties = { url: "not-a-valid-url" }

    assert_nil result[:properties][:host], "Expected host to be nil but got: #{result[:properties][:host].inspect}"
    assert_nil result[:properties][:path], "Expected path to be nil but got: #{result[:properties][:path].inspect}"
    assert_equal({}, result[:properties][:query_params])
  end

  test "handles invalid referrer gracefully" do
    @properties = { referrer: "not-a-valid-url" }

    assert_nil result[:properties][:referrer_host]
    assert_nil result[:properties][:referrer_path]
  end

  test "extracts all UTM parameters from query string" do
    @properties = {
      url: "https://example.com/pricing?utm_source=google&utm_medium=cpc&utm_campaign=spring&utm_content=ad1&utm_term=analytics"
    }

    assert_equal "google", result[:properties][:utm_source]
    assert_equal "cpc", result[:properties][:utm_medium]
    assert_equal "spring", result[:properties][:utm_campaign]
    assert_equal "ad1", result[:properties][:utm_content]
    assert_equal "analytics", result[:properties][:utm_term]
  end

  test "preserves existing UTM parameters if present" do
    @properties = {
      url: "https://example.com/pricing?utm_source=google",
      utm_source: "facebook"
    }

    assert_equal "facebook", result[:properties][:utm_source]
  end

  private

  def result
    service.call
  end

  def service
    Events::EnrichmentService.new(request_stub, event_data)
  end

  def event_data
    @event_data ||= {
      event_type: event_type,
      timestamp: timestamp,
      properties: properties
    }.compact
  end

  def event_type
    @event_type || "page_view"
  end

  def timestamp
    @timestamp
  end

  def properties
    @properties || { url: url }
  end

  def url
    @url || "https://example.com"
  end

  def request_stub
    ip_val = instance_variable_defined?(:@ip) ? @ip : "192.168.1.100"
    user_agent_val = instance_variable_defined?(:@user_agent) ? @user_agent : "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)"
    accept_language_val = instance_variable_defined?(:@accept_language) ? @accept_language : "en-US,en;q=0.9"
    dnt_val = instance_variable_defined?(:@dnt) ? @dnt : "1"

    headers = {}
    headers["Accept-Language"] = accept_language_val if accept_language_val
    headers["DNT"] = dnt_val if dnt_val

    stub = Object.new
    stub.define_singleton_method(:ip) { ip_val }
    stub.define_singleton_method(:user_agent) { user_agent_val }
    stub.define_singleton_method(:headers) { headers }
    stub
  end
end
