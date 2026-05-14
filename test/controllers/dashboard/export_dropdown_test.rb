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

  test "renders MCP row linking to the MCP docs" do
    get dashboard_path

    assert_select "a[data-testid='mcp-row'][href=?]", docs_path(page: "mcp"), text: /MCP/
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
