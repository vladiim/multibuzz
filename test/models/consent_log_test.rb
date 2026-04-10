# frozen_string_literal: true

require "test_helper"

class ConsentLogTest < ActiveSupport::TestCase
  # --- Validations ---

  test "valid with required fields" do
    assert_predicate build_log, :valid?
  end

  test "requires consent_payload" do
    log = build_log(consent_payload: nil)

    refute_predicate log, :valid?
  end

  test "requires ip_hash" do
    log = build_log(ip_hash: nil)

    refute_predicate log, :valid?
  end

  test "requires banner_version" do
    log = build_log(banner_version: nil)

    refute_predicate log, :valid?
  end

  test "country and visitor_id and account_id are optional" do
    log = build_log(country: nil, visitor_id: nil, account_id: nil)

    assert_predicate log, :valid?
  end

  # --- Relationships ---

  test "belongs to an account optionally" do
    log = build_log(account: accounts(:one))

    assert_equal accounts(:one), log.account
  end

  # --- Persistence ---

  test "persists with all fields" do
    log = build_log.tap(&:save!)

    assert_predicate log, :persisted?
    assert_equal "denied", log.consent_payload["analytics"]
  end

  private

  def build_log(**overrides)
    ConsentLog.new(
      consent_payload: { "ad" => "denied", "analytics" => "denied" },
      ip_hash: "abc123",
      banner_version: "v1",
      country: "FR",
      user_agent: "Test/1.0"
    ).tap { |log| overrides.each { |k, v| log.public_send("#{k}=", v) } }
  end
end
