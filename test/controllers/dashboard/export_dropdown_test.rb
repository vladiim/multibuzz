# frozen_string_literal: true

require "test_helper"

class Dashboard::ExportDropdownTest < ActionDispatch::IntegrationTest
  setup do
    accounts(:one).update!(live_mode_enabled: true)
    accounts(:one).data_integrity_checks.destroy_all
    sign_in_as users(:one)
  end

  test "renders Download CSV row" do
    get dashboard_path

    assert_response :success
    assert_select "[data-export-button-target='csvRow']", text: /Download CSV/
  end

  test "renders API row linking to API keys page" do
    get dashboard_path

    assert_response :success
    assert_select "a[href=?]", account_api_keys_path, text: /API/
  end

  test "renders greyed MCP row with soon pill" do
    get dashboard_path

    assert_select "[data-testid='mcp-row']" do
      assert_select "*", text: /MCP/
      assert_select "*", text: /soon/i
    end
  end

  test "MCP row is not a link until MCP ships" do
    get dashboard_path

    assert_select "[data-testid='mcp-row'] a", count: 0
  end

  test "API and MCP rows present on Events tab too" do
    get dashboard_path(tab: "events")

    assert_response :success
    assert_select "a[href=?]", account_api_keys_path, text: /API/
    assert_select "[data-testid='mcp-row']"
  end

  test "API row points users to data-downloads docs from the API keys page" do
    get account_api_keys_path

    assert_response :success
    assert_select "a[href=?]", docs_path(page: "data-downloads")
  end
end
