# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class AdPlatforms::Google::ApiUsageTrackerTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  # --- Constants ---

  test "daily operation limit is 15,000" do
    assert_equal 15_000, AdPlatforms::Google::ApiUsageTracker::DAILY_OPERATION_LIMIT
  end

  test "warning threshold is 80 percent" do
    assert_equal 80, AdPlatforms::Google::ApiUsageTracker::WARNING_THRESHOLD
  end

  # --- Increment ---

  test "increment increases current usage by 1" do
    tracker.increment!

    assert_equal 1, tracker.current_usage
  end

  test "increment increases by specified count" do
    tracker.increment!(5)

    assert_equal 5, tracker.current_usage
  end

  test "multiple increments accumulate" do
    tracker.increment!(3)
    tracker.increment!(7)

    assert_equal 10, tracker.current_usage
  end

  # --- Current Usage ---

  test "current usage returns 0 when no operations tracked" do
    assert_equal 0, tracker.current_usage
  end

  # --- Usage Percentage ---

  test "usage percentage returns 0 when no operations" do
    assert_equal 0, tracker.usage_percentage
  end

  test "usage percentage calculates correctly" do
    tracker.increment!(7_500)

    assert_equal 50, tracker.usage_percentage
  end

  test "usage percentage caps at 100" do
    tracker.increment!(20_000)

    assert_equal 100, tracker.usage_percentage
  end

  # --- Approaching Limit ---

  test "approaching limit is false below threshold" do
    tracker.increment!(11_000)

    assert_not tracker.approaching_limit?
  end

  test "approaching limit is true at threshold" do
    tracker.increment!(12_000)

    assert_predicate tracker, :approaching_limit?
  end

  test "approaching limit is true above threshold" do
    tracker.increment!(14_000)

    assert_predicate tracker, :approaching_limit?
  end

  # --- Remaining Operations ---

  test "remaining operations returns full limit when no usage" do
    assert_equal 15_000, tracker.remaining_operations
  end

  test "remaining operations decreases with usage" do
    tracker.increment!(5_000)

    assert_equal 10_000, tracker.remaining_operations
  end

  test "remaining operations floors at zero" do
    tracker.increment!(20_000)

    assert_equal 0, tracker.remaining_operations
  end

  # --- ApiClient instrumentation ---

  test "ApiClient increments tracker on each request" do
    stub_http do
      client = AdPlatforms::Google::ApiClient.new(access_token: "tok", customer_id: "123")
      client.search("SELECT campaign.id FROM campaign")
    end

    assert_equal 1, tracker.current_usage
  end

  private

  def tracker = AdPlatforms::Google::ApiUsageTracker

  def stub_http(&block)
    mock_response = Minitest::Mock.new
    mock_response.expect :is_a?, true, [ Net::HTTPSuccess ]
    mock_response.expect :body, { "results" => [] }.to_json

    AdPlatforms::Google.stub(:credentials, { developer_token: "test_token" }) do
      Net::HTTP.stub :start, ->(*, **, &blk) {
        mock_http = Minitest::Mock.new
        mock_http.expect(:request, mock_response, [ Net::HTTP::Post ])
        blk.call(mock_http)
      } do
        block.call
      end
    end
  end
end
