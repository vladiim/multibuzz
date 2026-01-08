require "test_helper"

class Visitors::LookupServiceTest < ActiveSupport::TestCase
  test "should find existing visitor" do
    assert result[:success]
    assert_equal visitor, result[:visitor]
    assert_not result[:created]
  end

  test "should create new visitor if not found" do
    @existing_visitor_id = "vis_new_visitor_123"

    assert_difference -> { Visitor.count }, 1 do
      assert result[:success]
      assert result[:created]
      assert_equal "vis_new_visitor_123", result[:visitor].visitor_id
      assert_equal account, result[:visitor].account
    end
  end

  test "should update last_seen_at for existing visitor" do
    old_time = 1.day.ago
    visitor.update_column(:last_seen_at, old_time)

    # Create fresh service instance to avoid memoization
    fresh_result = Visitors::LookupService.new(account, existing_visitor_id).call

    assert_in_delta Time.current, fresh_result[:visitor].last_seen_at, 1.second
  end

  test "should scope visitor to account" do
    assert_equal account, result[:visitor].account
  end

  test "should handle validation errors" do
    @existing_visitor_id = "a"  # Too short

    assert_not result[:success]
    assert result[:errors].present?
  end

  # --- Billing Usage ---

  test "should increment usage counter when visitor is created" do
    @existing_visitor_id = "vis_new_visitor_for_billing"

    assert_difference -> { usage_counter.current_usage }, 1 do
      result
    end
  end

  test "should not increment usage counter when visitor already exists" do
    assert_no_difference -> { usage_counter.current_usage } do
      result
    end
  end

  # --- Canonical Visitor Deduplication ---

  test "should use canonical visitor when recent session exists with same fingerprint" do
    fingerprint = "abc123def456"

    # Create a session with this fingerprint for the existing visitor
    account.sessions.create!(
      visitor: visitor,
      session_id: "sess_canonical_test",
      device_fingerprint: fingerprint,
      started_at: Time.current,
      last_activity_at: Time.current
    )

    # New visitor_id but same fingerprint should resolve to canonical visitor
    service_with_fingerprint = Visitors::LookupService.new(
      account,
      "vis_new_random_id_#{SecureRandom.hex(8)}",
      device_fingerprint: fingerprint
    )

    result = service_with_fingerprint.call

    assert result[:success]
    assert_not result[:created], "Should NOT create new visitor when canonical exists"
    assert_equal visitor.id, result[:visitor].id, "Should return canonical visitor"
    assert result[:canonical], "Should indicate canonical visitor was used"
  end

  test "should create new visitor when no recent session with fingerprint" do
    fingerprint = "unique_fingerprint_#{SecureRandom.hex(8)}"

    service_with_fingerprint = Visitors::LookupService.new(
      account,
      "vis_new_id_#{SecureRandom.hex(8)}",
      device_fingerprint: fingerprint
    )

    assert_difference -> { Visitor.count }, 1 do
      result = service_with_fingerprint.call
      assert result[:success]
      assert result[:created]
    end
  end

  test "should not use canonical visitor when session is older than 30 seconds" do
    fingerprint = "old_fingerprint_#{SecureRandom.hex(8)}"

    # Create a session with this fingerprint but older than 30 seconds
    account.sessions.create!(
      visitor: visitor,
      session_id: "sess_old_test",
      device_fingerprint: fingerprint,
      started_at: 1.minute.ago,
      created_at: 1.minute.ago,
      last_activity_at: 1.minute.ago
    )

    service_with_fingerprint = Visitors::LookupService.new(
      account,
      "vis_new_id_#{SecureRandom.hex(8)}",
      device_fingerprint: fingerprint
    )

    assert_difference -> { Visitor.count }, 1 do
      result = service_with_fingerprint.call
      assert result[:success]
      assert result[:created], "Should create new visitor when canonical session is too old"
    end
  end

  private

  def usage_counter
    @usage_counter ||= Billing::UsageCounter.new(account)
  end

  def result
    @result ||= service.call
  end

  def service
    @service ||= Visitors::LookupService.new(account, existing_visitor_id)
  end

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def existing_visitor_id
    @existing_visitor_id ||= visitor.visitor_id
  end
end
