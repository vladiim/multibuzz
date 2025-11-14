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
