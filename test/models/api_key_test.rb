require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  test "should be valid with valid attributes" do
    assert api_key.valid?
  end

  test "should belong to account" do
    assert_equal account, api_key.account
  end

  test "should require account" do
    api_key.account = nil

    assert_not api_key.valid?
    assert_includes api_key.errors[:account], "must exist"
  end

  test "should require key_digest" do
    api_key.key_digest = nil

    assert_not api_key.valid?
    assert_includes api_key.errors[:key_digest], "can't be blank"
  end

  test "should require unique key_digest" do
    duplicate = ApiKey.new(
      account: account,
      key_digest: api_key.key_digest,
      key_prefix: "sk_test_different",
      environment: "test"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key_digest], "has already been taken"
  end

  test "should require key_prefix" do
    api_key.key_prefix = nil

    assert_not api_key.valid?
    assert_includes api_key.errors[:key_prefix], "can't be blank"
  end

  test "should allow test and live environments" do
    api_key.test!
    assert api_key.test?

    api_key.live!
    assert api_key.live?
  end

  test "should default to not revoked" do
    new_key = ApiKey.new(
      account: account,
      key_digest: "digest",
      key_prefix: "sk_test_abc",
      environment: :test
    )

    assert_not new_key.revoked?
  end

  test "should be revocable" do
    assert_not api_key.revoked?

    api_key.revoke!

    assert api_key.revoked?
    assert api_key.revoked_at.present?
  end

  test "should track last_used_at" do
    new_key = ApiKey.create!(
      account: account,
      key_digest: "new_digest",
      key_prefix: "sk_test_new",
      environment: :test
    )

    assert_nil new_key.last_used_at

    new_key.record_usage!

    assert new_key.last_used_at.present?
    assert_in_delta Time.current, new_key.last_used_at, 1.second
  end

  test "should be active when not revoked" do
    assert api_key.active?

    api_key.revoke!

    assert_not api_key.active?
  end

  test "should scope active keys" do
    active_key = api_keys(:one)
    revoked_key = api_keys(:revoked)

    active_keys = ApiKey.active

    assert_includes active_keys, active_key
    assert_not_includes active_keys, revoked_key
  end

  test "should scope by environment" do
    test_keys = ApiKey.test
    live_keys = ApiKey.live

    assert_includes test_keys, api_keys(:one)
    assert_includes live_keys, api_keys(:live)
  end

  test "should display masked key" do
    api_key.key_prefix = "sk_test_abcd1234"

    assert_equal "sk_test_abcd1234••••••••••••••••••••", api_key.masked_key
  end

  private

  def api_key
    @api_key ||= api_keys(:one)
  end

  def account
    @account ||= accounts(:one)
  end
end
