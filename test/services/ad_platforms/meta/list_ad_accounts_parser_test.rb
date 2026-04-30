# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Meta::ListAdAccountsParserTest < ActiveSupport::TestCase
  test "returns active accounts only" do
    accounts = parser(body_with_mixed_statuses).accounts

    assert_equal 2, accounts.size
    assert_equal [ "act_TEST_001", "act_TEST_003" ], accounts.map { |a| a[:id] }
  end

  test "preserves the act_ prefix on ids" do
    accounts = parser(body_with_mixed_statuses).accounts

    assert accounts.all? { |a| a[:id].start_with?("act_") }
  end

  test "captures id and name" do
    parsed = parser(body_with_mixed_statuses).accounts.first

    assert_equal "act_TEST_001", parsed[:id]
    assert_equal "Test Sydney Location", parsed[:name]
  end

  test "captures currency and timezone_name" do
    parsed = parser(body_with_mixed_statuses).accounts.first

    assert_equal "AUD", parsed[:currency]
    assert_equal "Australia/Sydney", parsed[:timezone_name]
  end

  test "returns an empty array when data is empty" do
    assert_empty parser("data" => []).accounts
  end

  test "returns an empty array when body is empty hash" do
    assert_empty parser({}).accounts
  end

  test "tolerates a nil body" do
    assert_empty AdPlatforms::Meta::ListAdAccountsParser.new(body: nil).accounts
  end

  test "next_page_url returns nil when paging is absent" do
    assert_nil parser("data" => []).next_page_url
  end

  test "next_page_url returns the URL when paging.next is present" do
    body = body_with_mixed_statuses.merge(
      "paging" => { "next" => "https://graph.facebook.com/v19.0/me/adaccounts?cursor=NEXT" }
    )

    assert_equal "https://graph.facebook.com/v19.0/me/adaccounts?cursor=NEXT", parser(body).next_page_url
  end

  private

  def parser(body)
    AdPlatforms::Meta::ListAdAccountsParser.new(body: body)
  end

  def body_with_mixed_statuses
    {
      "data" => [
        {
          "id" => "act_TEST_001",
          "name" => "Test Sydney Location",
          "currency" => "AUD",
          "account_status" => 1,
          "timezone_name" => "Australia/Sydney"
        },
        {
          "id" => "act_TEST_002",
          "name" => "Test Disabled Account",
          "currency" => "AUD",
          "account_status" => 2,
          "timezone_name" => "Australia/Sydney"
        },
        {
          "id" => "act_TEST_003",
          "name" => "Test Brisbane Location",
          "currency" => "AUD",
          "account_status" => 1,
          "timezone_name" => "Australia/Brisbane"
        }
      ]
    }
  end
end
