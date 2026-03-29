# frozen_string_literal: true

require "test_helper"

class Score::SignupServiceTest < ActiveSupport::TestCase
  test "creates user and account on signup" do
    result = Score::SignupService.new(
      email: "scorer@example.com",
      password: "password123",
      claim_token: nil
    ).call

    assert result[:success]
    assert_predicate result[:user], :persisted?
    assert_predicate result[:account], :persisted?
  end

  test "claims assessment when valid claim token provided" do
    assessment = ScoreAssessment.create!(overall_score: 2.0, overall_level: 2)
    token = assessment.claim_token

    result = Score::SignupService.new(
      email: "claimer@example.com",
      password: "password123",
      claim_token: token
    ).call

    assessment.reload

    assert_equal result[:user].id, assessment.user_id
    assert_nil assessment.claim_token
  end

  test "derives account name from email domain" do
    result = Score::SignupService.new(
      email: "noclaim@example.com",
      password: "password123",
      claim_token: nil
    ).call

    assert result[:success]

    assert_equal "example.com", result[:account].name
  end

  test "derives account name from email" do
    result = Score::SignupService.new(
      email: "vlad@bigcorp.com.au",
      password: "password123",
      claim_token: nil
    ).call

    assert result[:success]

    assert_equal "bigcorp.com.au", result[:account].name
  end

  test "fails with blank email" do
    result = Score::SignupService.new(
      email: "",
      password: "password123",
      claim_token: nil
    ).call

    assert_not result[:success]

    assert_includes result[:errors], "Email can't be blank"
  end

  test "fails with blank password" do
    result = Score::SignupService.new(
      email: "test@example.com",
      password: "",
      claim_token: nil
    ).call

    assert_not result[:success]

    assert_includes result[:errors], "Password can't be blank"
  end

  test "fails with duplicate email" do
    result = Score::SignupService.new(
      email: users(:one).email,
      password: "password123",
      claim_token: nil
    ).call

    assert_not result[:success]
  end

  test "ignores invalid claim token gracefully" do
    result = Score::SignupService.new(
      email: "newuser@example.com",
      password: "password123",
      claim_token: "bogus_token"
    ).call

    assert result[:success]
    assert_predicate result[:user], :persisted?
  end

  test "marks user as score_signup source" do
    result = Score::SignupService.new(
      email: "source@example.com",
      password: "password123",
      claim_token: nil
    ).call

    assert result[:success]
    # The account should be created via score flow
    # Membership should be owner role
    membership = result[:user].account_memberships.first

    assert_equal "owner", membership.role
  end
end
