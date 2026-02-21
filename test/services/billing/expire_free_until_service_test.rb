# frozen_string_literal: true

require "test_helper"

class Billing::ExpireFreeUntilServiceTest < ActiveSupport::TestCase
  test "expires accounts with free_until in the past" do
    account.update!(billing_status: :free_until, free_until: 1.day.ago)

    service.call

    assert_predicate account.reload, :billing_expired?
  end

  test "does not expire accounts with free_until in the future" do
    account.update!(billing_status: :free_until, free_until: 7.days.from_now)

    service.call

    assert_predicate account.reload, :billing_free_until?
  end

  test "does not affect accounts with other billing statuses" do
    account.update!(billing_status: :active)

    service.call

    assert_predicate account.reload, :billing_active?
  end

  test "expires multiple accounts at once" do
    account.update!(billing_status: :free_until, free_until: 1.day.ago)
    other_account.update!(billing_status: :free_until, free_until: 2.days.ago)

    service.call

    assert_predicate account.reload, :billing_expired?
    assert_predicate other_account.reload, :billing_expired?
  end

  test "handles accounts expiring exactly now" do
    account.update!(billing_status: :free_until, free_until: Time.current)

    service.call

    assert_predicate account.reload, :billing_expired?
  end

  test "returns count of expired accounts" do
    account.update!(billing_status: :free_until, free_until: 1.day.ago)
    other_account.update!(billing_status: :free_until, free_until: 7.days.from_now)

    result = service.call

    assert result[:success]
    assert_equal 1, result[:expired_count]
  end

  private

  def service
    @service ||= Billing::ExpireFreeUntilService.new
  end

  def account
    @account ||= accounts(:one)
  end

  def other_account
    @other_account ||= accounts(:two)
  end
end
