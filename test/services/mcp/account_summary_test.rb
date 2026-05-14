# frozen_string_literal: true

require "test_helper"

class Mcp::AccountSummaryTest < ActiveSupport::TestCase
  EXPECTED_KEYS = %i[
    account_name environment first_event_at selected_sdk
    active_ad_platforms default_attribution_model available_funnels currencies
  ].freeze

  test "to_h returns the full snapshot shape" do
    assert_equal EXPECTED_KEYS.sort, summary(accounts(:one)).to_h.keys.sort
  end

  test "reports the account name" do
    assert_equal accounts(:one).name, summary(accounts(:one)).to_h[:account_name]
  end

  test "environment reflects the api key" do
    assert_equal "test", summary(accounts(:one), api_keys(:one)).to_h[:environment]
    assert_equal "live", summary(accounts(:one), api_keys(:live)).to_h[:environment]
  end

  test "lists the account's connected ad platforms" do
    assert_includes summary(accounts(:one)).to_h[:active_ad_platforms], "google_ads"
  end

  test "a fresh account yields empty collections and no first event" do
    result = summary(empty_account).to_h

    assert_empty result[:active_ad_platforms]
    assert_empty result[:available_funnels]
    assert_nil result[:first_event_at]
  end

  test "the snapshot is account-scoped" do
    assert_not_equal(
      summary(accounts(:one)).to_h[:account_name],
      summary(accounts(:two)).to_h[:account_name]
    )
  end

  private

  def summary(account, api_key = api_keys(:one))
    Mcp::Resources::AccountSummary.new(account: account, api_key: api_key)
  end

  def empty_account
    @empty_account ||= Account.create!(name: "Fresh MCP", slug: "fresh-mcp-#{SecureRandom.hex(3)}")
  end
end
