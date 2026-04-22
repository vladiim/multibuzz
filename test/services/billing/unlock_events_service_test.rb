# frozen_string_literal: true

require "test_helper"

class Billing::UnlockEventsServiceTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "unlocks all locked events for account" do
    create_locked_event
    create_locked_event

    result = service.call

    assert result[:success]
    assert_equal 2, result[:unlocked_count]
    assert_predicate account.events.where(locked: true), :none?
  end

  test "returns zero when no locked events" do
    result = service.call

    assert result[:success]
    assert_equal 0, result[:unlocked_count]
  end

  test "only unlocks events for specified account" do
    create_locked_event
    other_event = create_locked_event(account: other_account)

    service.call

    assert_predicate account.events.where(locked: true), :none?
    assert_predicate other_event.reload, :locked?
  end

  test "enqueues a single BatchReattributionJob covering all conversions in the locked period" do
    create_locked_event(occurred_at: 5.days.ago)
    create_locked_event(occurred_at: 1.day.ago)
    conversion_a = create_conversion(converted_at: 4.days.ago)
    conversion_b = create_conversion(converted_at: 2.days.ago)

    assert_enqueued_with(job: Conversions::BatchReattributionJob, args: [ [ conversion_a.id, conversion_b.id ] ]) do
      service.call
    end
  end

  test "does not enqueue reattribution for conversions outside locked period" do
    create_locked_event(occurred_at: 3.days.ago)
    create_conversion(converted_at: 10.days.ago)

    assert_no_enqueued_jobs(only: Conversions::BatchReattributionJob) do
      service.call
    end
  end

  test "records unlocked period in result" do
    create_locked_event(occurred_at: 5.days.ago)
    create_locked_event(occurred_at: 2.days.ago)

    result = service.call

    assert_predicate result[:earliest_unlocked], :present?
    assert_predicate result[:latest_unlocked], :present?
    assert_operator result[:earliest_unlocked], :<, result[:latest_unlocked]
  end

  test "updates account billing status when past_due" do
    account.update!(billing_status: :past_due, payment_failed_at: 5.days.ago)
    create_locked_event

    service.call

    assert_predicate account.reload, :billing_active?
  end

  test "clears payment failure timestamps" do
    account.update!(
      billing_status: :past_due,
      payment_failed_at: 5.days.ago,
      grace_period_ends_at: 2.days.ago
    )
    create_locked_event

    service.call

    account.reload

    assert_nil account.payment_failed_at
    assert_nil account.grace_period_ends_at
  end

  private

  def service
    @service ||= Billing::UnlockEventsService.new(account)
  end

  def account
    @account ||= accounts(:one)
  end

  def other_account
    @other_account ||= accounts(:two)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def session
    @session ||= sessions(:one)
  end

  def create_locked_event(account: self.account, occurred_at: 1.day.ago)
    Event.create!(
      account: account,
      visitor: account == self.account ? visitor : visitors(:two),
      session: account == self.account ? session : sessions(:two),
      event_type: "page_view",
      occurred_at: occurred_at,
      locked: true,
      properties: { url: "https://example.com" }
    )
  end

  def create_conversion(converted_at:)
    Conversion.create!(
      account: account,
      visitor: visitor,
      session_id: session.id,
      conversion_type: "purchase",
      converted_at: converted_at,
      revenue: 100.00
    )
  end
end
