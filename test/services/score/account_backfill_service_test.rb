# frozen_string_literal: true

require "test_helper"

class Score::AccountBackfillServiceTest < ActiveSupport::TestCase
  test "assigns account when user has exactly one active membership" do
    assessment = create_unassigned_assessment(user: solo_user)

    result = service.call

    assessment.reload

    assert result[:success]
    assert_equal solo_account.id, assessment.account_id
    assert_equal 1, result[:assigned]
  end

  test "skips when user has multiple active memberships" do
    assessment = create_unassigned_assessment(user: multi_user)

    result = service.call

    assessment.reload

    assert_nil assessment.account_id
    assert_equal 1, result[:skipped_multi_membership]
  end

  test "skips when assessment has no user" do
    assessment = ScoreAssessment.create!(overall_score: 1.5, overall_level: 1)

    result = service.call

    assessment.reload

    assert_nil assessment.account_id
    assert_equal 0, result[:assigned]
  end

  test "leaves already-assigned assessments untouched" do
    assessment = ScoreAssessment.create!(
      overall_score: 2.0, overall_level: 2,
      user: solo_user, account: accounts(:two)
    )

    service.call

    assessment.reload

    assert_equal accounts(:two).id, assessment.account_id
  end

  test "summary counts cover all branches" do
    create_unassigned_assessment(user: solo_user)
    create_unassigned_assessment(user: multi_user)
    create_unassigned_assessment(user: multi_user)

    result = service.call

    assert result[:success]
    assert_equal 1, result[:assigned]
    assert_equal 2, result[:skipped_multi_membership]
  end

  private

  def service = @service ||= Score::AccountBackfillService.new

  def solo_user = @solo_user ||= users(:two)
  def solo_account = @solo_account ||= accounts(:two)
  def multi_user = @multi_user ||= users(:one)

  def create_unassigned_assessment(user:)
    ScoreAssessment.create!(overall_score: 2.0, overall_level: 2, user: user)
  end
end
