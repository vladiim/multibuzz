require "test_helper"

class Billing::UsageCounterTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  # --- Reading Usage ---

  test "current_usage returns zero when no events tracked" do
    assert_equal 0, counter.current_usage
  end

  test "current_usage returns cached count" do
    Rails.cache.write(cache_key, 500)

    assert_equal 500, counter.current_usage
  end

  # --- Incrementing Usage ---

  test "increment! increases usage count" do
    counter.increment!

    assert_equal 1, counter.current_usage
  end

  test "increment! accepts custom count" do
    counter.increment!(5)

    assert_equal 5, counter.current_usage
  end

  test "increment! is cumulative" do
    counter.increment!(10)
    counter.increment!(5)

    assert_equal 15, counter.current_usage
  end

  # --- Limit Checking ---

  test "within_limit? returns true when under limit" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 5000)

    assert counter.within_limit?
  end

  test "within_limit? returns false when at limit" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 10_000)

    assert_not counter.within_limit?
  end

  test "within_limit? returns false when over limit" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 15_000)

    assert_not counter.within_limit?
  end

  # --- Usage Percentage ---

  test "usage_percentage calculates correctly" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 8000)

    assert_equal 80, counter.usage_percentage
  end

  test "usage_percentage caps at 100" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 15_000)

    assert_equal 100, counter.usage_percentage
  end

  test "usage_percentage returns 0 when no usage" do
    account.update!(plan: free_plan)

    assert_equal 0, counter.usage_percentage
  end

  # --- Threshold Checks ---

  test "approaching_limit? returns true at 80%" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 8000)

    assert counter.approaching_limit?
  end

  test "approaching_limit? returns false below 80%" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 7000)

    assert_not counter.approaching_limit?
  end

  test "at_limit? returns true at 100%" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 10_000)

    assert counter.at_limit?
  end

  test "at_limit? returns false below 100%" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 9000)

    assert_not counter.at_limit?
  end

  # --- Event Limit ---

  test "event_limit returns plan events_included" do
    account.update!(plan: starter_plan)

    assert_equal 50_000, counter.event_limit
  end

  test "event_limit defaults to FREE_EVENT_LIMIT when no plan" do
    account.update!(plan: nil)

    assert_equal Billing::FREE_EVENT_LIMIT, counter.event_limit
  end

  # --- Reset ---

  test "reset! clears the usage counter" do
    Rails.cache.write(cache_key, 5000)

    counter.reset!

    assert_equal 0, counter.current_usage
  end

  # --- Remaining Events ---

  test "remaining_events calculates correctly" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 3000)

    assert_equal 7000, counter.remaining_events
  end

  test "remaining_events returns 0 when over limit" do
    account.update!(plan: free_plan)
    Rails.cache.write(cache_key, 15_000)

    assert_equal 0, counter.remaining_events
  end

  private

  def counter
    @counter ||= Billing::UsageCounter.new(account)
  end

  def account
    @account ||= accounts(:one)
  end

  def free_plan
    @free_plan ||= plans(:free)
  end

  def starter_plan
    @starter_plan ||= plans(:starter)
  end

  def cache_key
    account.usage_cache_key
  end
end
