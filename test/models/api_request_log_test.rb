require "test_helper"

class ApiRequestLogTest < ActiveSupport::TestCase
  # --- Validations ---

  test "should be valid with valid attributes" do
    assert log.valid?
  end

  test "should require request_id" do
    log.request_id = nil

    assert_not log.valid?
    assert_includes log.errors[:request_id], "can't be blank"
  end

  test "should require endpoint" do
    log.endpoint = nil

    assert_not log.valid?
    assert_includes log.errors[:endpoint], "can't be blank"
  end

  test "should require http_method" do
    log.http_method = nil

    assert_not log.valid?
    assert_includes log.errors[:http_method], "can't be blank"
  end

  test "should require http_status" do
    log.http_status = nil

    assert_not log.valid?
    assert_includes log.errors[:http_status], "can't be blank"
  end

  test "should require error_type" do
    log.error_type = nil

    assert_not log.valid?
    assert_includes log.errors[:error_type], "can't be blank"
  end

  test "should require occurred_at" do
    log.occurred_at = nil

    assert_not log.valid?
    assert_includes log.errors[:occurred_at], "can't be blank"
  end

  # --- Enum ---

  test "should have auth error types" do
    assert ApiRequestLog.error_types.key?("auth_missing_header")
    assert ApiRequestLog.error_types.key?("auth_malformed_header")
    assert ApiRequestLog.error_types.key?("auth_invalid_key")
    assert ApiRequestLog.error_types.key?("auth_revoked_key")
    assert ApiRequestLog.error_types.key?("auth_account_suspended")
  end

  test "should have validation error types" do
    assert ApiRequestLog.error_types.key?("validation_missing_param")
    assert ApiRequestLog.error_types.key?("validation_invalid_format")
  end

  test "should have business error types" do
    assert ApiRequestLog.error_types.key?("visitor_not_found")
    assert ApiRequestLog.error_types.key?("rate_limit_exceeded")
    assert ApiRequestLog.error_types.key?("billing_blocked")
  end

  test "should have server error types" do
    assert ApiRequestLog.error_types.key?("internal_error")
  end

  test "should provide enum predicate methods" do
    log.error_type = :auth_missing_header

    assert log.auth_missing_header?
    assert_not log.visitor_not_found?
  end

  test "should provide enum bang methods" do
    log.visitor_not_found!

    assert log.visitor_not_found?
  end

  # --- Relationships ---

  test "should belong to account optionally" do
    log.account = nil

    assert log.valid?
  end

  test "should belong to account when present" do
    log.account = account

    assert_equal account, log.account
  end

  # --- Scopes ---

  test "should scope by account" do
    log.save!

    assert_includes ApiRequestLog.by_account(account), log
    assert_not_includes ApiRequestLog.by_account(accounts(:two)), log
  end

  test "should scope by error type" do
    log.error_type = :visitor_not_found
    log.save!

    assert_includes ApiRequestLog.by_error_type(:visitor_not_found), log
    assert_not_includes ApiRequestLog.by_error_type(:auth_missing_header), log
  end

  test "should scope recent logs" do
    log.occurred_at = 1.hour.ago
    log.save!

    old_log = ApiRequestLog.create!(
      account: account,
      request_id: SecureRandom.uuid,
      endpoint: "events",
      http_method: "POST",
      http_status: 422,
      error_type: :visitor_not_found,
      occurred_at: 25.hours.ago
    )

    assert_includes ApiRequestLog.recent(24.hours), log
    assert_not_includes ApiRequestLog.recent(24.hours), old_log
  end

  test "should scope by endpoint" do
    log.save!

    assert_includes ApiRequestLog.by_endpoint("events"), log
    assert_not_includes ApiRequestLog.by_endpoint("conversions"), log
  end

  # --- JSONB columns ---

  test "should store error_details as jsonb" do
    log.error_details = { index: 0, event_type: "page_view" }
    log.save!
    log.reload

    assert_equal 0, log.error_details["index"]
    assert_equal "page_view", log.error_details["event_type"]
  end

  test "should store request_params as jsonb" do
    log.request_params = { visitor_id: "vis_123", event_type: "signup" }
    log.save!
    log.reload

    assert_equal "vis_123", log.request_params["visitor_id"]
  end

  test "should default error_details to empty hash" do
    new_log = ApiRequestLog.new
    assert_equal({}, new_log.error_details)
  end

  test "should default request_params to empty hash" do
    new_log = ApiRequestLog.new
    assert_equal({}, new_log.request_params)
  end

  private

  def log
    @log ||= ApiRequestLog.new(
      account: account,
      request_id: SecureRandom.uuid,
      endpoint: "events",
      http_method: "POST",
      http_status: 422,
      error_type: :visitor_not_found,
      error_message: "Visitor not found",
      occurred_at: Time.current
    )
  end

  def account
    @account ||= accounts(:one)
  end
end
