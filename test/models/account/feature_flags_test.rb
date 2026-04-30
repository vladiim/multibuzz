# frozen_string_literal: true

require "test_helper"

class Account::FeatureFlagsTest < ActiveSupport::TestCase
  test "feature_enabled? returns false when flag is not set" do
    refute account_one.feature_enabled?(:meta_ads_integration)
  end

  test "feature_enabled? returns true after enable_feature!" do
    account_one.enable_feature!(:meta_ads_integration)

    assert account_one.feature_enabled?(:meta_ads_integration)
  end

  test "feature_enabled? returns false after disable_feature!" do
    account_one.enable_feature!(:meta_ads_integration)
    account_one.disable_feature!(:meta_ads_integration)

    refute account_one.feature_enabled?(:meta_ads_integration)
  end

  test "enable_feature! is idempotent" do
    account_one.enable_feature!(:meta_ads_integration)
    account_one.enable_feature!(:meta_ads_integration)

    assert_equal 1, account_one.feature_flags.where(flag_name: "meta_ads_integration").count
  end

  test "disable_feature! is a no-op when flag is not set" do
    assert_nothing_raised { account_one.disable_feature!(:meta_ads_integration) }
  end

  test "feature_enabled? accepts symbol or string" do
    account_one.enable_feature!(:meta_ads_integration)

    assert account_one.feature_enabled?(:meta_ads_integration)
    assert account_one.feature_enabled?("meta_ads_integration")
  end

  test "enable_feature! accepts string and symbol identically" do
    account_one.enable_feature!("meta_ads_integration")

    assert account_one.feature_enabled?(:meta_ads_integration)
  end

  test "flags are isolated per account" do
    account_one.enable_feature!(:meta_ads_integration)

    refute account_two.feature_enabled?(:meta_ads_integration)
  end

  test "memoization invalidates on enable_feature!" do
    refute account_one.feature_enabled?(:meta_ads_integration)
    account_one.enable_feature!(:meta_ads_integration)

    assert account_one.feature_enabled?(:meta_ads_integration)
  end

  test "memoization invalidates on disable_feature!" do
    account_one.enable_feature!(:meta_ads_integration)

    assert account_one.feature_enabled?(:meta_ads_integration)
    account_one.disable_feature!(:meta_ads_integration)

    refute account_one.feature_enabled?(:meta_ads_integration)
  end

  test "destroying account cascades feature flags" do
    account = Account.create!(name: "Cascadia", slug: "cascadia-#{SecureRandom.hex(4)}", status: 0)
    account.enable_feature!(:meta_ads_integration)

    assert_difference "AccountFeatureFlag.count", -1 do
      account.destroy!
    end
  end

  private

  def account_one = @account_one ||= accounts(:one)
  def account_two = @account_two ||= accounts(:two)
end
