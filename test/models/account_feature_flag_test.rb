# frozen_string_literal: true

require "test_helper"

class AccountFeatureFlagTest < ActiveSupport::TestCase
  test "is valid with account and flag_name" do
    assert_predicate build_flag(account: account_one, flag_name: "meta_ads_integration"), :valid?
  end

  test "requires flag_name" do
    refute_predicate build_flag(account: account_one, flag_name: nil), :valid?
  end

  test "requires account" do
    refute_predicate build_flag(account: nil, flag_name: "meta_ads_integration"), :valid?
  end

  test "is invalid when same flag exists for same account" do
    AccountFeatureFlag.create!(account: account_one, flag_name: "meta_ads_integration")

    refute_predicate build_flag(account: account_one, flag_name: "meta_ads_integration"), :valid?
  end

  test "is valid when same flag exists for different account" do
    AccountFeatureFlag.create!(account: account_one, flag_name: "meta_ads_integration")

    assert_predicate build_flag(account: account_two, flag_name: "meta_ads_integration"), :valid?
  end

  test "belongs to account" do
    flag = AccountFeatureFlag.create!(account: account_one, flag_name: "meta_ads_integration")

    assert_equal account_one, flag.account
  end

  private

  def build_flag(account:, flag_name:)
    AccountFeatureFlag.new(account: account, flag_name: flag_name)
  end

  def account_one = @account_one ||= accounts(:one)
  def account_two = @account_two ||= accounts(:two)
end
