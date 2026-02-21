# frozen_string_literal: true

require "test_helper"

class ApiRequestLogs::RecordServiceTest < ActiveSupport::TestCase
  # --- Basic Recording ---

  test "should create api request log" do
    assert_difference -> { ApiRequestLog.count }, 1 do
      result
    end

    assert result[:success]
  end

  test "should record error type" do
    result

    assert_equal "auth_missing_header", log_record.error_type
  end

  test "should record error message" do
    result

    assert_equal "Missing Authorization header", log_record.error_message
  end

  test "should record http status" do
    result

    assert_equal 401, log_record.http_status
  end

  test "should record endpoint" do
    result

    assert_equal "v1/events", log_record.endpoint
  end

  test "should record http method" do
    result

    assert_equal "POST", log_record.http_method
  end

  test "should record occurred_at" do
    freeze_time do
      result

      assert_equal Time.current, log_record.occurred_at
    end
  end

  # --- Account Attribution ---

  test "should link to account when provided" do
    result

    assert_equal account, log_record.account
  end

  test "should allow nil account for auth failures" do
    @account = nil

    assert_difference -> { ApiRequestLog.count }, 1 do
      result
    end

    assert_nil log_record.account
  end

  # --- Request ID ---

  test "should use request_id from request when available" do
    @request_id = "req_123456"

    result

    assert_equal "req_123456", log_record.request_id
  end

  test "should generate uuid when request_id not available" do
    @request_id = nil

    result

    assert_match(/\A[0-9a-f-]{36}\z/, log_record.request_id)
  end

  # --- SDK Parsing ---

  test "should parse sdk name from user agent" do
    @user_agent = "mbuzz-ruby/0.7.1"

    result

    assert_equal "mbuzz-ruby", log_record.sdk_name
  end

  test "should parse sdk version from user agent" do
    @user_agent = "mbuzz-ruby/0.7.1"

    result

    assert_equal "0.7.1", log_record.sdk_version
  end

  test "should handle php sdk user agent" do
    @user_agent = "mbuzz-php/1.2.3"

    result

    assert_equal "mbuzz-php", log_record.sdk_name
    assert_equal "1.2.3", log_record.sdk_version
  end

  test "should handle node sdk user agent" do
    @user_agent = "mbuzz-node/2.0.0"

    result

    assert_equal "mbuzz-node", log_record.sdk_name
    assert_equal "2.0.0", log_record.sdk_version
  end

  test "should set unknown for non-sdk user agent" do
    @user_agent = "Mozilla/5.0 Chrome/120.0"

    result

    assert_equal "unknown", log_record.sdk_name
    assert_nil log_record.sdk_version
  end

  test "should handle nil user agent" do
    @user_agent = nil

    result

    assert_nil log_record.sdk_name
    assert_nil log_record.sdk_version
  end

  # --- IP Anonymization ---

  test "should anonymize ipv4 address" do
    @remote_ip = "192.168.1.123"

    result

    assert_equal "192.168.1.0", log_record.ip_address
  end

  test "should preserve first three octets" do
    @remote_ip = "10.20.30.40"

    result

    assert_equal "10.20.30.0", log_record.ip_address
  end

  test "should handle nil ip address" do
    @remote_ip = nil

    result

    assert_nil log_record.ip_address
  end

  # --- Error Details ---

  test "should store error details" do
    @error_details = { index: 0, event_type: "page_view" }.freeze

    result

    assert_equal 0, log_record.error_details["index"]
    assert_equal "page_view", log_record.error_details["event_type"]
  end

  test "should default error details to empty hash" do
    @error_details = nil

    result

    assert_empty(log_record.error_details)
  end

  # --- Request Params Sanitization ---

  test "should store allowed request params" do
    @params = ActionController::Parameters.new(
      event_type: "page_view",
      visitor_id: "vis_123",
      session_id: "sess_456"
    )

    result

    assert_equal "page_view", log_record.request_params["event_type"]
    assert_equal "vis_123", log_record.request_params["visitor_id"]
  end

  test "should exclude sensitive params" do
    @params = ActionController::Parameters.new(
      event_type: "page_view",
      password: "secret123",
      api_key: "sk_test_xxx",
      token: "bearer_xxx"
    )

    result

    assert_equal "page_view", log_record.request_params["event_type"]
    assert_nil log_record.request_params["password"]
    assert_nil log_record.request_params["api_key"]
    assert_nil log_record.request_params["token"]
  end

  # --- User Agent Storage ---

  test "should store full user agent" do
    @user_agent = "mbuzz-ruby/0.7.1 (Rails 8.0)"

    result

    assert_equal "mbuzz-ruby/0.7.1 (Rails 8.0)", log_record.user_agent
  end

  private

  def result
    @result ||= service.call
  end

  def service
    @service ||= ApiRequestLogs::RecordService.new(
      request: mock_request,
      account: resolved_account,
      error_type: error_type,
      error_message: error_message,
      http_status: http_status,
      error_details: error_details
    )
  end

  MockRequest = Struct.new(:request_id, :path, :method, :user_agent, :remote_ip, :content_length, :params, keyword_init: true)

  def mock_request
    @mock_request ||= MockRequest.new(
      request_id: request_id,
      path: "/api/v1/events",
      method: "POST",
      user_agent: user_agent,
      remote_ip: remote_ip,
      content_length: 1024,
      params: params
    )
  end

  def request_id
    return @request_id if defined?(@request_id)
    @request_id = "req_test_123"
  end

  def user_agent
    return @user_agent if defined?(@user_agent)
    @user_agent = "mbuzz-ruby/0.7.1"
  end

  def remote_ip
    return @remote_ip if defined?(@remote_ip)
    @remote_ip = "192.168.1.100"
  end

  def params
    return @params if defined?(@params)
    @params = ActionController::Parameters.new(event_type: "page_view", visitor_id: "vis_123")
  end

  def resolved_account
    return @account if defined?(@account)
    account
  end

  def account
    @_account ||= accounts(:one)
  end

  def error_type
    @error_type ||= :auth_missing_header
  end

  def error_message
    @error_message ||= "Missing Authorization header"
  end

  def http_status
    @http_status ||= 401
  end

  def error_details
    return @error_details if defined?(@error_details)
    @error_details = {}
  end

  def log_record
    @log_record ||= ApiRequestLog.last
  end
end
