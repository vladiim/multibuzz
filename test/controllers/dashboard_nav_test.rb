# frozen_string_literal: true

require "test_helper"

class DashboardNavTest < ActionDispatch::IntegrationTest
  setup do
    accounts(:one).update!(onboarding_progress: (1 << Account::Onboarding::ONBOARDING_STEPS.size) - 1)
  end

  test "account dropdown shows maturity entry pointing to score dashboard for assessed account" do
    create_assessment(account: accounts(:one), level: 2)
    sign_in_as(users(:one))

    get dashboard_path

    assert_response :success
    assert_select "a[href='#{score_dashboard_path}']", text: /Measurement Maturity.*Level 2/m
  end

  test "account dropdown shows take-assessment entry when current account has none" do
    sign_in_as(users(:one))

    get dashboard_path

    assert_response :success
    assert_select "a[href='#{score_path}']", text: /Take Measurement Assessment/
  end

  test "each membership row shows a level pill for its own account" do
    create_assessment(account: accounts(:one), level: 1)
    create_assessment(account: accounts(:two), level: 4)
    sign_in_as(users(:one))

    get dashboard_path

    assert_response :success
    assert_select ".account-level-pill", text: "L1"
    assert_select ".account-level-pill", text: "L4"
  end

  private

  def create_assessment(account:, level:)
    ScoreAssessment.create!(
      account: account,
      overall_score: level.to_f,
      overall_level: level,
      dimension_scores: {},
      answers: []
    )
  end
end
