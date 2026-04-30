# frozen_string_literal: true

require "test_helper"

class Admin::FeatureFlagsControllerTest < ActionDispatch::IntegrationTest
  test "non-admin user is redirected" do
    sign_in_as(regular_user)

    get admin_feature_flags_path

    assert_redirected_to root_path
  end

  test "admin sees index" do
    sign_in_as(admin_user)

    get admin_feature_flags_path

    assert_response :success
  end

  test "create enables flag for given account" do
    sign_in_as(admin_user)

    assert_difference -> { account_one.feature_flags.count }, 1 do
      post admin_feature_flags_path, params: {
        account_id: account_one.id,
        flag_name: FeatureFlags::META_ADS_INTEGRATION
      }
    end

    assert account_one.feature_enabled?(FeatureFlags::META_ADS_INTEGRATION)
  end

  test "create with unknown flag_name is rejected and creates nothing" do
    sign_in_as(admin_user)

    assert_no_difference "AccountFeatureFlag.count" do
      post admin_feature_flags_path, params: {
        account_id: account_one.id,
        flag_name: "made_up_flag"
      }
    end
  end

  test "destroy disables flag" do
    sign_in_as(admin_user)
    account_one.enable_feature!(FeatureFlags::META_ADS_INTEGRATION)

    assert_difference -> { account_one.feature_flags.count }, -1 do
      delete admin_feature_flags_path, params: {
        account_id: account_one.id,
        flag_name: FeatureFlags::META_ADS_INTEGRATION
      }
    end

    refute account_one.reload.feature_enabled?(FeatureFlags::META_ADS_INTEGRATION)
  end

  test "destroy is idempotent when flag is not set" do
    sign_in_as(admin_user)

    assert_no_difference "AccountFeatureFlag.count" do
      delete admin_feature_flags_path, params: {
        account_id: account_one.id,
        flag_name: FeatureFlags::META_ADS_INTEGRATION
      }
    end
  end

  test "create on one account does not affect another account" do
    sign_in_as(admin_user)

    post admin_feature_flags_path, params: {
      account_id: account_one.id,
      flag_name: FeatureFlags::META_ADS_INTEGRATION
    }

    refute account_two.feature_enabled?(FeatureFlags::META_ADS_INTEGRATION)
  end

  test "non-admin cannot create flag" do
    sign_in_as(regular_user)

    assert_no_difference "AccountFeatureFlag.count" do
      post admin_feature_flags_path, params: {
        account_id: account_one.id,
        flag_name: FeatureFlags::META_ADS_INTEGRATION
      }
    end
  end

  private

  def admin_user = @admin_user ||= users(:admin)
  def regular_user = @regular_user ||= users(:one)
  def account_one = @account_one ||= accounts(:one)
  def account_two = @account_two ||= accounts(:two)
end
