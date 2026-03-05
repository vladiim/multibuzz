# frozen_string_literal: true

require "test_helper"

module Demo
  class DashboardPagesTest < ActionDispatch::IntegrationTest
    test "demo dashboard loads with spend tab and browse button" do
      get demo_dashboard_path

      assert_response :success
      assert_select "button", text: "Spend"
      assert_select "a", text: /Browse/
    end

    test "demo spend tab loads" do
      get demo_dashboard_spend_path

      assert_response :success
    end

    test "demo conversion list loads" do
      get demo_dashboard_conversion_list_path

      assert_response :success
      assert_select "h1", text: "Conversions"
    end

    test "demo conversion detail loads" do
      get demo_dashboard_conversion_detail_path("conv_demo_001")

      assert_response :success
      assert_select "h1", text: "Purchase"
    end

    test "demo conversion detail redirects for invalid id" do
      get demo_dashboard_conversion_detail_path("nonexistent")

      assert_redirected_to demo_dashboard_conversion_list_path
    end
  end
end
