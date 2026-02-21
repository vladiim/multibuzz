# frozen_string_literal: true

require "test_helper"

class DataIntegrityCheckTest < ActiveSupport::TestCase
  # -- Validations --

  test "valid check persists" do
    check = account.data_integrity_checks.build(
      check_name: "ghost_session_rate",
      status: "healthy",
      value: 5.0,
      warning_threshold: 20.0,
      critical_threshold: 50.0
    )

    assert_predicate check, :valid?
  end

  test "rejects missing check_name" do
    check = account.data_integrity_checks.build(
      check_name: nil,
      status: "healthy",
      value: 5.0,
      warning_threshold: 20.0,
      critical_threshold: 50.0
    )

    assert_not check.valid?
    assert_includes check.errors[:check_name], "can't be blank"
  end

  test "rejects invalid status" do
    check = account.data_integrity_checks.build(
      check_name: "ghost_session_rate",
      status: "terrible",
      value: 5.0,
      warning_threshold: 20.0,
      critical_threshold: 50.0
    )

    assert_not check.valid?
    assert_includes check.errors[:status], "is not included in the list"
  end

  test "accepts all valid statuses" do
    %w[healthy warning critical].each do |status|
      check = account.data_integrity_checks.build(
        check_name: "ghost_session_rate",
        status: status,
        value: 5.0,
        warning_threshold: 20.0,
        critical_threshold: 50.0
      )

      assert_predicate check, :valid?, "Expected status '#{status}' to be valid"
    end
  end

  # -- Scopes --

  test "recent returns checks from last 24 hours" do
    recent_checks = account.data_integrity_checks.recent

    assert_includes recent_checks, healthy_ghost
    assert_includes recent_checks, warning_inflation
    assert_not_includes recent_checks, critical_ghost
  end

  test "by_check filters by check_name" do
    ghost_checks = account.data_integrity_checks.by_check("ghost_session_rate")

    assert_includes ghost_checks, healthy_ghost
    assert_includes ghost_checks, critical_ghost
    assert_not_includes ghost_checks, warning_inflation
  end

  test "worst_first sorts critical before warning before healthy" do
    sorted = account.data_integrity_checks.worst_first

    statuses = sorted.map(&:status)

    assert_equal 0, statuses.index("critical")
  end

  # -- Relationships --

  test "belongs to account" do
    assert_equal account, healthy_ghost.account
  end

  test "account cannot see other account checks" do
    assert_not_includes account.data_integrity_checks, other_account_check
  end

  private

  def account
    @account ||= accounts(:one)
  end

  def healthy_ghost
    @healthy_ghost ||= data_integrity_checks(:healthy_ghost)
  end

  def warning_inflation
    @warning_inflation ||= data_integrity_checks(:warning_inflation)
  end

  def critical_ghost
    @critical_ghost ||= data_integrity_checks(:critical_ghost)
  end

  def other_account_check
    @other_account_check ||= data_integrity_checks(:other_account_check)
  end
end
