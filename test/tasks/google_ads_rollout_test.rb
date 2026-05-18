# frozen_string_literal: true

require "test_helper"
require "rake"

class GoogleAdsRolloutTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
  end

  test "enable_for_paid_accounts enables the flag for paid accounts without it" do
    paid = build_account(plan: plans(:starter))

    capture_stdout { run_task("google_ads_rollout:enable_for_paid_accounts") }

    assert paid.reload.feature_enabled?(FeatureFlags::GOOGLE_ADS_INTEGRATION)
  end

  test "enable_for_paid_accounts skips accounts on the free plan" do
    free = build_account(plan: plans(:free))

    capture_stdout { run_task("google_ads_rollout:enable_for_paid_accounts") }

    refute free.reload.feature_enabled?(FeatureFlags::GOOGLE_ADS_INTEGRATION)
  end

  test "enable_for_paid_accounts skips accounts with no plan" do
    no_plan = build_account(plan: nil)

    capture_stdout { run_task("google_ads_rollout:enable_for_paid_accounts") }

    refute no_plan.reload.feature_enabled?(FeatureFlags::GOOGLE_ADS_INTEGRATION)
  end

  test "enable_for_paid_accounts is idempotent" do
    paid = build_account(plan: plans(:growth))
    paid.enable_feature!(FeatureFlags::GOOGLE_ADS_INTEGRATION)
    initial_count = paid.feature_flags.where(flag_name: FeatureFlags::GOOGLE_ADS_INTEGRATION).count

    capture_stdout { run_task("google_ads_rollout:enable_for_paid_accounts") }

    assert_equal initial_count,
      paid.reload.feature_flags.where(flag_name: FeatureFlags::GOOGLE_ADS_INTEGRATION).count
  end

  test "enable_for_paid_accounts prints a summary" do
    build_account(plan: plans(:starter))
    build_account(plan: plans(:growth))
    build_account(plan: plans(:free))

    output = capture_stdout { run_task("google_ads_rollout:enable_for_paid_accounts") }

    assert_match(/Enabled.*GOOGLE_ADS_INTEGRATION|Enabled .* for acct_/i, output)
    assert_match(/Enabled:\s*\d+/i, output)
    assert_match(/Already on:\s*\d+/i, output)
  end

  test "DRY_RUN previews without enabling" do
    paid = build_account(plan: plans(:starter))

    output = capture_stdout do
      ENV["DRY_RUN"] = "true"
      run_task("google_ads_rollout:enable_for_paid_accounts")
    ensure
      ENV.delete("DRY_RUN")
    end

    refute paid.reload.feature_enabled?(FeatureFlags::GOOGLE_ADS_INTEGRATION)
    assert_match(/DRY RUN/i, output)
  end

  private

  def run_task(name)
    Rake::Task[name].reenable
    Rake::Task[name].invoke
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  def build_account(plan:)
    Account.create!(
      name: "Rollout Test #{SecureRandom.hex(4)}",
      slug: "rollout-test-#{SecureRandom.hex(4)}",
      plan: plan
    )
  end
end
