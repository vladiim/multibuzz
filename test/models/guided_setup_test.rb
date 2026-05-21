# frozen_string_literal: true

require "test_helper"

class GuidedSetupTest < ActiveSupport::TestCase
  test "is valid with an account" do
    assert_predicate guided_setup, :valid?
  end

  test "defaults to pending" do
    assert_predicate guided_setup, :pending?
  end

  test "defaults the integration target to none" do
    assert_predicate guided_setup, :integration_none?
  end

  test "mark_in_progress! sets the status and stamps accepted_at" do
    guided_setup.mark_in_progress!

    assert_predicate guided_setup, :in_progress?
    assert_predicate guided_setup.accepted_at, :present?
  end

  test "record_milestone! stamps the milestone timestamp" do
    guided_setup.record_milestone!(:kickoff_call)

    assert_predicate guided_setup.kickoff_call_at, :present?
  end

  test "recording the value check delivers the engagement" do
    guided_setup.mark_in_progress!
    guided_setup.record_milestone!(:value_check)

    assert_predicate guided_setup, :delivered?
    assert_predicate guided_setup.completed_at, :present?
  end

  test "record_milestone! rejects an unknown milestone" do
    assert_raises(ArgumentError) { guided_setup.record_milestone!(:lunch) }
  end

  test "cancel! marks the engagement cancelled" do
    guided_setup.cancel!

    assert_predicate guided_setup, :cancelled?
  end

  test "stalled scope is in-progress engagements untouched for over 14 days" do
    stale = GuidedSetup.create!(account: accounts(:one))
    stale.update_columns(status: GuidedSetup.statuses[:in_progress], updated_at: 20.days.ago)
    fresh = GuidedSetup.create!(account: accounts(:two), status: :in_progress)

    assert_includes GuidedSetup.stalled, stale
    assert_not_includes GuidedSetup.stalled, fresh
  end

  test "rejects scheduling_preferences with an unknown timezone" do
    guided_setup.scheduling_preferences = { "timezone" => "Mars/Olympus" }

    assert_not guided_setup.valid?
    assert_includes guided_setup.errors[:scheduling_preferences].join, "unknown timezone"
  end

  test "rejects scheduling_preferences with unknown day-of-week values" do
    guided_setup.scheduling_preferences = { "timezone" => "Sydney", "days" => [ "tue", "funday" ] }

    assert_not guided_setup.valid?
    assert_includes guided_setup.errors[:scheduling_preferences].join, "day-of-week"
  end

  test "accepts a fully-populated scheduling_preferences hash" do
    guided_setup.scheduling_preferences = {
      "timezone" => "Sydney",
      "days" => [ "tue", "wed" ],
      "time_blocks" => [ "morning", "afternoon" ]
    }

    assert_predicate guided_setup, :valid?
  end

  test "allows only one engagement per account" do
    GuidedSetup.create!(account: account)
    duplicate = GuidedSetup.new(account: account)

    assert_not duplicate.valid?
  end

  test "exposes a prefixed id" do
    assert_match(/\Agst_/, guided_setup.prefix_id)
  end

  test "is reachable from its account" do
    assert_equal guided_setup, account.reload.guided_setup
  end

  test "integration_target_for picks Meta when the customer runs Meta ads" do
    profile = { "ad_platforms" => [ "meta", "tiktok" ] }

    assert_equal "meta", GuidedSetup.integration_target_for(profile)
  end

  test "integration_target_for prefers Meta over Google Ads when both are run" do
    profile = { "ad_platforms" => [ "google_ads", "meta" ] }

    assert_equal "meta", GuidedSetup.integration_target_for(profile)
  end

  test "integration_target_for picks Google Ads when Meta is absent" do
    profile = { "ad_platforms" => [ "google_ads", "linkedin" ] }

    assert_equal "google_ads", GuidedSetup.integration_target_for(profile)
  end

  test "integration_target_for picks sGTM when only sGTM install is planned" do
    profile = { "ad_platforms" => [ "none" ], "install_platforms" => [ "sgtm" ] }

    assert_equal "sgtm", GuidedSetup.integration_target_for(profile)
  end

  test "integration_target_for falls back to none when nothing matches" do
    assert_equal "none", GuidedSetup.integration_target_for({})
    assert_equal "none", GuidedSetup.integration_target_for(nil)
  end

  test "stalled? is true for an in-progress engagement untouched for over 14 days" do
    guided_setup.update_columns(status: GuidedSetup.statuses[:in_progress], updated_at: 20.days.ago)

    assert_predicate guided_setup, :stalled?
  end

  test "stalled? is false for a recently-touched engagement" do
    guided_setup.update!(status: :in_progress)

    assert_not guided_setup.stalled?
  end

  private

  def account = @account ||= accounts(:one)

  def guided_setup
    @guided_setup ||= GuidedSetup.create!(account: account)
  end
end
