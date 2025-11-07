require "test_helper"

class ApiKeys::RateLimiterServiceTest < ActiveSupport::TestCase
  setup do
    Rails.cache.clear
  end

  test "should allow request within limit" do
    assert result[:allowed]
    assert_equal 999, result[:remaining]
    assert result[:reset_at].present?
  end

  test "should track request count" do
    service.call

    second_result = service.call
    assert second_result[:allowed]
    assert_equal 998, second_result[:remaining]
  end

  test "should reject request when limit exceeded" do
    1000.times { service.call }

    assert_not result[:allowed]
    assert_equal 0, result[:remaining]
    assert_equal "Rate limit exceeded", result[:error]
  end

  test "should reset after window expires" do
    1000.times { service.call }

    # Simulate cache expiration by clearing
    Rails.cache.delete("rate_limit:account:#{account.id}")

    travel 1.hour do
      fresh_service = ApiKeys::RateLimiterService.new(account)
      fresh_result = fresh_service.call

      assert fresh_result[:allowed]
      assert_equal 999, fresh_result[:remaining]
    end
  end

  test "should use per-account rate limiting" do
    other_account = accounts(:two)
    other_service = ApiKeys::RateLimiterService.new(other_account)

    1000.times { service.call }

    assert_not service.call[:allowed]
    assert other_service.call[:allowed]
  end

  test "should include retry_after when rate limited" do
    1000.times { service.call }

    assert_not result[:allowed]
    assert result[:retry_after].present?
    assert result[:retry_after] > 0
  end

  test "should use custom limit if provided" do
    custom_service = ApiKeys::RateLimiterService.new(account, limit: 5)

    5.times { custom_service.call }

    assert_not custom_service.call[:allowed]
    assert_equal 0, custom_service.call[:remaining]
  end

  test "should use custom window if provided" do
    custom_service = ApiKeys::RateLimiterService.new(account, window: 10)

    1000.times { custom_service.call }

    assert_not custom_service.call[:allowed]

    # Simulate cache expiration by clearing
    Rails.cache.delete("rate_limit:account:#{account.id}")

    travel 11.seconds do
      fresh_service = ApiKeys::RateLimiterService.new(account, window: 10)
      assert fresh_service.call[:allowed]
    end
  end

  private

  def result
    @result ||= service.call
  end

  def service
    @service ||= ApiKeys::RateLimiterService.new(account)
  end

  def account
    @account ||= accounts(:one)
  end
end
