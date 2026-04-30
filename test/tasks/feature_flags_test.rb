# frozen_string_literal: true

require "test_helper"
require "rake"

class FeatureFlagsTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  test "feature_flags:enable enables the flag for the given account" do
    capture_stdout do
      run_task("feature_flags:enable", acct: account_one.prefix_id, flag: FeatureFlags::META_ADS_INTEGRATION)
    end

    assert account_one.feature_enabled?(FeatureFlags::META_ADS_INTEGRATION)
  end

  test "feature_flags:enable is idempotent" do
    capture_stdout do
      2.times do
        run_task("feature_flags:enable", acct: account_one.prefix_id, flag: FeatureFlags::META_ADS_INTEGRATION)
      end
    end

    assert_equal 1, account_one.feature_flags.where(flag_name: FeatureFlags::META_ADS_INTEGRATION).count
  end

  test "feature_flags:disable removes the flag" do
    account_one.enable_feature!(FeatureFlags::META_ADS_INTEGRATION)

    capture_stdout do
      run_task("feature_flags:disable", acct: account_one.prefix_id, flag: FeatureFlags::META_ADS_INTEGRATION)
    end

    refute account_one.reload.feature_enabled?(FeatureFlags::META_ADS_INTEGRATION)
  end

  test "feature_flags:list prints flags for the account" do
    account_one.enable_feature!(FeatureFlags::META_ADS_INTEGRATION)

    output = capture_stdout do
      run_task("feature_flags:list", acct: account_one.prefix_id)
    end

    assert_includes output, FeatureFlags::META_ADS_INTEGRATION
  end

  test "feature_flags:accounts lists accounts with the given flag" do
    account_one.enable_feature!(FeatureFlags::META_ADS_INTEGRATION)

    output = capture_stdout do
      run_task("feature_flags:accounts", flag: FeatureFlags::META_ADS_INTEGRATION)
    end

    assert_includes output, account_one.prefix_id
  end

  test "feature_flags:enable rejects unknown flag names" do
    assert_raises(SystemExit) do
      capture_stdout do
        run_task("feature_flags:enable", acct: account_one.prefix_id, flag: "made_up")
      end
    end
  end

  test "feature_flags:enable rejects unknown account prefix" do
    assert_raises(SystemExit) do
      capture_stdout do
        run_task("feature_flags:enable", acct: "acct_doesnotexist", flag: FeatureFlags::META_ADS_INTEGRATION)
      end
    end
  end

  private

  def run_task(name, env_vars = {})
    previous = env_vars.transform_keys { |k| k.to_s.upcase }.to_h { |k, _| [ k, ENV[k] ] }
    env_vars.each { |k, v| ENV[k.to_s.upcase] = v.to_s }
    Rake::Task[name].reenable
    Rake::Task[name].invoke
  ensure
    previous.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def account_one = @account_one ||= accounts(:one)
end
