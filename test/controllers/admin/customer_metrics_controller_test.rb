# frozen_string_literal: true

require "test_helper"

class Admin::CustomerMetricsControllerTest < ActionDispatch::IntegrationTest
  test "redirects non-admins to root" do
    sign_in_as(users(:one))

    get admin_customer_metrics_path

    assert_redirected_to root_path
  end

  test "renders the index for admins" do
    sign_in_as(users(:admin))

    get admin_customer_metrics_path

    assert_response :success
    assert_select "table"
  end

  test "lists every account name" do
    sign_in_as(users(:admin))

    get admin_customer_metrics_path

    Account.find_each { |a| assert_includes response.body, a.name }
  end

  test "csv export responds with text/csv content type" do
    sign_in_as(users(:admin))

    get admin_customer_metrics_path(format: :csv)

    assert_match(%r{text/csv}, response.media_type)
  end

  test "csv export body includes the headline column headers" do
    sign_in_as(users(:admin))

    get admin_customer_metrics_path(format: :csv)

    assert_includes response.body, "Account"
    assert_includes response.body, "LTV"
  end
end
