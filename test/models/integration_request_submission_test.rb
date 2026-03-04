# frozen_string_literal: true

require "test_helper"

class IntegrationRequestSubmissionTest < ActiveSupport::TestCase
  # --- validations ---

  test "valid with coming soon platform" do
    assert_predicate submission(platform_name: "Meta Ads"), :valid?
  end

  test "valid with request-only platform" do
    assert_predicate submission(platform_name: "Amazon Ads"), :valid?
  end

  test "invalid without platform_name" do
    refute_predicate submission(platform_name: nil), :valid?
  end

  test "invalid with unknown platform_name" do
    refute_predicate submission(platform_name: "Myspace Ads"), :valid?
  end

  test "requires platform_name_other when Other selected" do
    sub = submission(platform_name: "Other", platform_name_other: nil)

    refute_predicate sub, :valid?
    assert_predicate sub.errors[:platform_name_other], :any?
  end

  test "valid with Other and platform_name_other" do
    assert_predicate submission(platform_name: "Other", platform_name_other: "Spotify Ads"), :valid?
  end

  test "monthly_spend is optional" do
    assert_predicate submission(monthly_spend: nil), :valid?
  end

  test "monthly_spend validates inclusion when present" do
    refute_predicate submission(monthly_spend: "a billion dollars"), :valid?
  end

  test "monthly_spend accepts valid option" do
    assert_predicate submission(monthly_spend: "$1K – $10K"), :valid?
  end

  # --- constants ---

  test "COMING_SOON_PLATFORMS is frozen" do
    assert_predicate IntegrationRequestSubmission::COMING_SOON_PLATFORMS, :frozen?
  end

  test "REQUEST_ONLY_PLATFORMS is frozen" do
    assert_predicate IntegrationRequestSubmission::REQUEST_ONLY_PLATFORMS, :frozen?
  end

  test "PLATFORM_OPTIONS includes both lists" do
    assert_includes IntegrationRequestSubmission::PLATFORM_OPTIONS, "Meta Ads"
    assert_includes IntegrationRequestSubmission::PLATFORM_OPTIONS, "Other"
  end

  # --- STI ---

  test "inherits from FormSubmission" do
    assert_kind_of FormSubmission, submission
  end

  test "stores platform_name in data JSONB" do
    sub = submission(platform_name: "Reddit Ads")
    sub.save!
    sub.reload

    assert_equal "Reddit Ads", sub.platform_name
    assert_equal "Reddit Ads", sub.data["platform_name"]
  end

  private

  def submission(overrides = {})
    IntegrationRequestSubmission.new({
      email: "test@example.com",
      platform_name: "Meta Ads"
    }.merge(overrides))
  end
end
