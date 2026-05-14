# frozen_string_literal: true

require "test_helper"

class Mcp::ToolsTest < ActiveSupport::TestCase
  META_KEYS = %i[total_count page per_page total_pages].freeze

  test "get_conversions returns the data/meta shape" do
    response = Mcp::Tools::GetConversions.call(**tool_args)

    assert_not response.error?
    assert_kind_of Array, response.structured_content[:data]
    assert_equal META_KEYS.sort, response.structured_content[:meta].keys.sort
  end

  test "get_funnel returns the data/meta shape" do
    response = Mcp::Tools::GetFunnel.call(**tool_args)

    assert_not response.error?
    assert_kind_of Array, response.structured_content[:data]
    assert_equal META_KEYS.sort, response.structured_content[:meta].keys.sort
  end

  test "get_spend returns the data/meta shape" do
    response = Mcp::Tools::GetSpend.call(**tool_args)

    assert_not response.error?
    assert_kind_of Array, response.structured_content[:data]
    assert_equal META_KEYS.sort, response.structured_content[:meta].keys.sort
  end

  test "a malformed date yields an error response, not a raised exception" do
    response = Mcp::Tools::GetConversions.call(**tool_args(start_date: "not-a-date", end_date: "2026-05-01"))

    assert_predicate response, :error?
    assert_match(/date/i, JSON.parse(response.content.first[:text])["error"])
  end

  test "tools scope to the account in server_context" do
    response = Mcp::Tools::GetSpend.call(**tool_args(account: empty_account))

    assert_not response.error?
    assert_empty response.structured_content[:data]
    assert_equal 0, response.structured_content[:meta][:total_count]
  end

  test "the api key in server_context drives test vs live data scope" do
    assert_not Mcp::Tools::GetSpend.call(**tool_args(api_key: api_keys(:one))).error?
    assert_not Mcp::Tools::GetSpend.call(**tool_args(api_key: api_keys(:live))).error?
  end

  private

  def tool_args(account: accounts(:one), api_key: api_keys(:one), **overrides)
    { server_context: { account: account, api_key: api_key } }.merge(overrides)
  end

  def empty_account
    @empty_account ||= Account.create!(name: "Empty MCP", slug: "empty-mcp-#{SecureRandom.hex(3)}")
  end
end
