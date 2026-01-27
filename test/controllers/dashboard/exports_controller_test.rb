# frozen_string_literal: true

require "test_helper"

class Dashboard::ExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    accounts(:one).update!(onboarding_progress: (1 << Account::Onboarding::ONBOARDING_STEPS.size) - 1)
  end

  test "returns CSV with attachment disposition" do
    sign_in
    post dashboard_export_path

    assert_response :success
    assert_equal "text/csv", response.content_type
    assert_match "attachment", response.headers["Content-Disposition"]
  end

  test "filename includes current date" do
    sign_in
    post dashboard_export_path

    assert_match "multibuzz-export-#{Date.current}.csv", response.headers["Content-Disposition"]
  end

  test "requires authentication" do
    post dashboard_export_path

    assert_response :redirect
  end

  test "returns 200 with empty data" do
    sign_in
    AttributionCredit.delete_all

    post dashboard_export_path

    assert_response :success
    csv = CSV.parse(response.body, headers: true)
    assert_equal 0, csv.size
  end

  private

  def sign_in
    post login_path, params: { email: users(:one).email, password: "password123" }
  end
end
