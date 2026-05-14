# frozen_string_literal: true

require "test_helper"

class Admin::DashboardControllerTest < ActionDispatch::IntegrationTest
  test "admin sees the index" do
    sign_in_as(admin_user)

    get admin_root_path

    assert_response :success
  end

  test "non-admin users are redirected with access denied" do
    sign_in_as(regular_user)

    get admin_root_path

    assert_redirected_to root_path
    assert_equal "Access denied.", flash[:alert]
  end

  test "unauthenticated users are redirected to login" do
    get admin_root_path

    assert_redirected_to login_path
  end

  test "every registered tool name appears on the page" do
    sign_in_as(admin_user)

    get admin_root_path

    AdminTools::ALL.each do |tool|
      assert_includes response.body, tool.name
    end
  end

  test "every registered tool path appears as a link" do
    sign_in_as(admin_user)

    get admin_root_path

    AdminTools::ALL.each do |tool|
      assert_select "a[href='#{tool.path}']"
    end
  end

  test "categories appear as headings" do
    sign_in_as(admin_user)

    get admin_root_path

    AdminTools.grouped.each_key do |category|
      assert_includes response.body, category
    end
  end

  private

  def admin_user = @admin_user ||= users(:admin)
  def regular_user = @regular_user ||= users(:one)
end
