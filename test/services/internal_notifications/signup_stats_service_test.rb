# frozen_string_literal: true

require "test_helper"

class InternalNotifications::SignupStatsServiceTest < ActiveSupport::TestCase
  test "exposes total_accounts as an integer" do
    assert_kind_of Integer, stats[:total_accounts]
  end

  test "exposes signups_today, signups_this_week, signups_this_month as integers" do
    %i[signups_today signups_this_week signups_this_month].each do |key|
      assert_kind_of Integer, stats[key], "expected #{key} to be an Integer"
    end
  end

  test "trial_to_paid_rate_30d sits within a 0..100 percentage range" do
    rate = stats[:trial_to_paid_rate_30d]

    assert (0..100).cover?(rate), "expected #{rate.inspect} between 0 and 100"
  end

  test "signups_today counts accounts created within the last 24 hours" do
    Account.create!(name: "Today One", slug: "today-one-#{SecureRandom.hex(4)}", created_at: 1.hour.ago)
    Account.create!(name: "Way Back", slug: "way-back-#{SecureRandom.hex(4)}", created_at: 10.days.ago)

    stats = InternalNotifications::SignupStatsService.new.call

    assert_operator stats[:signups_today], :>=, 1
  end

  test "trial_to_paid_rate_30d reports the conversion percentage of the 30-day cohort" do
    Account.create!(name: "Paid Convert", slug: "paid-#{SecureRandom.hex(4)}", created_at: 10.days.ago, billing_status: :active, subscription_started_at: 5.days.ago)
    Account.create!(name: "Still Trial", slug: "trial-#{SecureRandom.hex(4)}", created_at: 10.days.ago, billing_status: :trialing)

    assert_operator stats[:trial_to_paid_rate_30d], :>, 0
  end

  private

  def stats = @stats ||= InternalNotifications::SignupStatsService.new.call
end
