# frozen_string_literal: true

require "test_helper"

class ApiRequestLoggingTest < ActionDispatch::IntegrationTest
  setup do
    Rails.cache.clear
  end

  # --- Auth Failures ---

  test "should log missing authorization header" do
    assert_difference -> { ApiRequestLog.count }, 1 do
      post api_v1_events_path, params: events_payload, as: :json
    end

    assert_response :unauthorized

    log = ApiRequestLog.last

    assert_equal "auth_missing_header", log.error_type
    assert_equal 401, log.http_status
    assert_equal "v1/events", log.endpoint
    assert_nil log.account
  end

  test "should log invalid api key" do
    assert_difference -> { ApiRequestLog.count }, 1 do
      post api_v1_events_path,
        params: events_payload,
        headers: { "Authorization" => "Bearer sk_test_invalid123" },
        as: :json
    end

    assert_response :unauthorized

    log = ApiRequestLog.last

    assert_equal "auth_invalid_key", log.error_type
    assert_equal 401, log.http_status
  end

  test "should log revoked api key" do
    api_key.revoke!

    assert_difference -> { ApiRequestLog.count }, 1 do
      post api_v1_events_path, params: events_payload, headers: auth_headers, as: :json
    end

    assert_response :unauthorized

    log = ApiRequestLog.last

    assert_equal "auth_revoked_key", log.error_type
  end

  test "should log suspended account" do
    account.suspended!

    assert_difference -> { ApiRequestLog.count }, 1 do
      post api_v1_events_path, params: events_payload, headers: auth_headers, as: :json
    end

    assert_response :unauthorized

    log = ApiRequestLog.last

    assert_equal "auth_account_suspended", log.error_type
    assert_equal account, log.account
  end

  # --- Event Rejections ---

  test "should log visitor not found rejection" do
    payload = {
      events: [
        {
          "event_type" => "page_view",
          "visitor_id" => "vis_unknown_#{SecureRandom.hex(8)}",
          "timestamp" => Time.current.iso8601
        }
      ]
    }

    assert_difference -> { ApiRequestLog.count }, 1 do
      post api_v1_events_path, params: payload, headers: auth_headers, as: :json
    end

    assert_response :accepted

    log = ApiRequestLog.last

    assert_equal "visitor_not_found", log.error_type
    assert_equal 422, log.http_status
    assert_equal account, log.account
  end

  test "should log validation error for invalid event" do
    payload = {
      events: [
        { "event_type" => "", "visitor_id" => visitor.visitor_id }
      ]
    }

    assert_difference -> { ApiRequestLog.count }, 1 do
      post api_v1_events_path, params: payload, headers: auth_headers, as: :json
    end

    assert_response :accepted

    log = ApiRequestLog.last

    assert_equal "validation_invalid_format", log.error_type
    assert_equal 422, log.http_status
  end

  test "should log multiple rejections in single request" do
    payload = {
      events: [
        { "event_type" => "" },
        { "event_type" => "page_view", "visitor_id" => "vis_unknown" }
      ]
    }

    assert_difference -> { ApiRequestLog.count }, 2 do
      post api_v1_events_path, params: payload, headers: auth_headers, as: :json
    end

    assert_response :accepted
  end

  test "should not log successful events" do
    payload = {
      events: [
        {
          "event_type" => "page_view",
          "visitor_id" => visitor.visitor_id,
          "timestamp" => Time.current.iso8601
        }
      ]
    }

    assert_no_difference -> { ApiRequestLog.count } do
      post api_v1_events_path, params: payload, headers: auth_headers, as: :json
    end

    assert_response :accepted
    assert_equal 1, json_response["accepted"]
  end

  # --- Conversion Failures ---

  test "should log conversion visitor not found" do
    payload = {
      conversion: {
        visitor_id: "vis_unknown_#{SecureRandom.hex(8)}",
        conversion_type: "purchase"
      }
    }

    assert_difference -> { ApiRequestLog.count }, 1 do
      post api_v1_conversions_path, params: payload, headers: auth_headers, as: :json
    end

    assert_response :unprocessable_entity

    log = ApiRequestLog.last

    assert_equal "visitor_not_found", log.error_type
    assert_equal "v1/conversions", log.endpoint
  end

  test "should log conversion missing type" do
    payload = {
      conversion: {
        visitor_id: visitor.visitor_id
      }
    }

    assert_difference -> { ApiRequestLog.count }, 1 do
      post api_v1_conversions_path, params: payload, headers: auth_headers, as: :json
    end

    assert_response :unprocessable_entity

    log = ApiRequestLog.last

    assert_equal "validation_missing_param", log.error_type
  end

  # --- Session Failures ---

  test "should log session creation failure" do
    payload = {
      session: {
        visitor_id: "",
        session_id: "",
        url: ""
      }
    }

    assert_difference -> { ApiRequestLog.count }, 1 do
      post api_v1_sessions_path, params: payload, headers: auth_headers, as: :json
    end

    assert_response :unprocessable_entity

    log = ApiRequestLog.last

    assert_equal "validation_missing_param", log.error_type
    assert_equal "v1/sessions", log.endpoint
  end

  # --- SDK Version Tracking ---

  test "should capture sdk version from user agent" do
    post api_v1_events_path,
      params: events_payload,
      headers: { "User-Agent" => "mbuzz-ruby/0.7.1" },
      as: :json

    log = ApiRequestLog.last

    assert_equal "mbuzz-ruby", log.sdk_name
    assert_equal "0.7.1", log.sdk_version
  end

  test "should capture php sdk version" do
    post api_v1_events_path,
      params: events_payload,
      headers: { "User-Agent" => "mbuzz-php/1.0.0" },
      as: :json

    log = ApiRequestLog.last

    assert_equal "mbuzz-php", log.sdk_name
    assert_equal "1.0.0", log.sdk_version
  end

  # --- IP Anonymization ---

  test "should anonymize ip address in logs" do
    post api_v1_events_path, params: events_payload, as: :json

    log = ApiRequestLog.last

    assert_predicate log.ip_address, :present?
    assert log.ip_address.end_with?(".0"), "IP should be anonymized"
  end

  private

  def json_response
    JSON.parse(response.body)
  end

  def auth_headers
    { "Authorization" => "Bearer #{plaintext_key}" }
  end

  def events_payload
    {
      events: [
        {
          "event_type" => "page_view",
          "visitor_id" => visitor.visitor_id,
          "timestamp" => Time.current.iso8601
        }
      ]
    }
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def account
    @account ||= accounts(:one)
  end

  def api_key
    @api_key ||= api_keys(:one)
  end

  def plaintext_key
    @plaintext_key ||= begin
      key = "sk_test_#{SecureRandom.hex(16)}"
      api_key.update_column(:key_digest, Digest::SHA256.hexdigest(key))
      key
    end
  end
end
