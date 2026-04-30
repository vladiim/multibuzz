# frozen_string_literal: true

require "test_helper"

class AdPlatforms::ApiUsageTrackerTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  # --- Constants ---

  test "warning threshold is 80 percent" do
    assert_equal 80, AdPlatforms::ApiUsageTracker::WARNING_THRESHOLD
  end

  test "google_ads daily limit is 15,000" do
    assert_equal 15_000, tracker.daily_limit_for(:google_ads)
  end

  test "meta_ads daily limit is 200,000" do
    assert_equal 200_000, tracker.daily_limit_for(:meta_ads)
  end

  test "tracked platforms returns keys of LIMITS" do
    assert_equal [ :google_ads, :meta_ads ], tracker.tracked_platforms
  end

  test "display_name_for returns the human name for each platform" do
    assert_equal "Google Ads", tracker.display_name_for(:google_ads)
    assert_equal "Meta Ads", tracker.display_name_for(:meta_ads)
  end

  # --- Increment ---

  test "increment increases current usage by 1" do
    tracker.increment!(:google_ads)

    assert_equal 1, tracker.current_usage(:google_ads)
  end

  test "increment increases by specified count" do
    tracker.increment!(:meta_ads, 5)

    assert_equal 5, tracker.current_usage(:meta_ads)
  end

  test "multiple increments accumulate" do
    tracker.increment!(:google_ads, 3)
    tracker.increment!(:google_ads, 7)

    assert_equal 10, tracker.current_usage(:google_ads)
  end

  test "platforms are isolated from each other" do
    tracker.increment!(:google_ads, 5_000)
    tracker.increment!(:meta_ads, 100)

    assert_equal 5_000, tracker.current_usage(:google_ads)
    assert_equal 100, tracker.current_usage(:meta_ads)
  end

  # --- Current Usage ---

  test "current usage returns 0 when no operations tracked" do
    assert_equal 0, tracker.current_usage(:google_ads)
    assert_equal 0, tracker.current_usage(:meta_ads)
  end

  # --- Usage Percentage ---

  test "usage percentage returns 0 when no operations" do
    assert_equal 0, tracker.usage_percentage(:google_ads)
  end

  test "usage percentage calculates correctly for google_ads" do
    tracker.increment!(:google_ads, 7_500)

    assert_equal 50, tracker.usage_percentage(:google_ads)
  end

  test "usage percentage calculates correctly for meta_ads" do
    tracker.increment!(:meta_ads, 100_000)

    assert_equal 50, tracker.usage_percentage(:meta_ads)
  end

  test "usage percentage caps at 100" do
    tracker.increment!(:google_ads, 20_000)

    assert_equal 100, tracker.usage_percentage(:google_ads)
  end

  # --- Approaching Limit ---

  test "approaching limit is false below threshold" do
    tracker.increment!(:google_ads, 11_000)

    assert_not tracker.approaching_limit?(:google_ads)
  end

  test "approaching limit is true at threshold" do
    tracker.increment!(:google_ads, 12_000)

    assert tracker.approaching_limit?(:google_ads)
  end

  test "approaching limit is true above threshold" do
    tracker.increment!(:meta_ads, 190_000)

    assert tracker.approaching_limit?(:meta_ads)
  end

  test "approaching limit is independent per platform" do
    tracker.increment!(:google_ads, 14_000)

    assert tracker.approaching_limit?(:google_ads)
    assert_not tracker.approaching_limit?(:meta_ads)
  end

  # --- Remaining Operations ---

  test "remaining operations returns full limit when no usage" do
    assert_equal 15_000, tracker.remaining_operations(:google_ads)
    assert_equal 200_000, tracker.remaining_operations(:meta_ads)
  end

  test "remaining operations decreases with usage" do
    tracker.increment!(:google_ads, 5_000)

    assert_equal 10_000, tracker.remaining_operations(:google_ads)
  end

  test "remaining operations floors at zero" do
    tracker.increment!(:meta_ads, 250_000)

    assert_equal 0, tracker.remaining_operations(:meta_ads)
  end

  # --- Unknown platforms fail loudly ---

  test "daily_limit_for raises on unknown platform" do
    assert_raises(KeyError) { tracker.daily_limit_for(:tiktok_ads) }
  end

  test "display_name_for raises on unknown platform" do
    assert_raises(KeyError) { tracker.display_name_for(:tiktok_ads) }
  end

  private

  def tracker = AdPlatforms::ApiUsageTracker
end
