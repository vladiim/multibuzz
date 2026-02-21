# frozen_string_literal: true

require "test_helper"

class FeatureWaitlistSubmissionTest < ActiveSupport::TestCase
  test "valid with all required fields" do
    submission = FeatureWaitlistSubmission.new(
      email: "test@example.com",
      feature_key: "data_export",
      feature_name: "Data Export"
    )

    assert_predicate submission, :valid?
  end

  test "requires email" do
    submission = FeatureWaitlistSubmission.new(
      feature_key: "data_export",
      feature_name: "Data Export"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:email], "can't be blank"
  end

  test "requires feature_key" do
    submission = FeatureWaitlistSubmission.new(
      email: "test@example.com",
      feature_name: "Data Export"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:feature_key], "can't be blank"
  end

  test "requires feature_name" do
    submission = FeatureWaitlistSubmission.new(
      email: "test@example.com",
      feature_key: "data_export"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:feature_name], "can't be blank"
  end

  test "validates feature_key is in valid list" do
    submission = FeatureWaitlistSubmission.new(
      email: "test@example.com",
      feature_key: "invalid_feature",
      feature_name: "Invalid Feature"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:feature_key], "is not a valid feature"
  end

  test "allows data_export feature" do
    submission = FeatureWaitlistSubmission.new(
      email: "test@example.com",
      feature_key: "data_export",
      feature_name: "Data Export"
    )

    assert_predicate submission, :valid?
  end

  test "allows csv_export feature" do
    submission = FeatureWaitlistSubmission.new(
      email: "test@example.com",
      feature_key: "csv_export",
      feature_name: "CSV Export"
    )

    assert_predicate submission, :valid?
  end

  test "allows api_extract feature" do
    submission = FeatureWaitlistSubmission.new(
      email: "test@example.com",
      feature_key: "api_extract",
      feature_name: "API Extract"
    )

    assert_predicate submission, :valid?
  end

  test "context is optional" do
    submission = FeatureWaitlistSubmission.new(
      email: "test@example.com",
      feature_key: "data_export",
      feature_name: "Data Export"
    )

    assert_predicate submission, :valid?
    assert_nil submission.context
  end

  test "stores context via store_accessor" do
    submission = FeatureWaitlistSubmission.new(
      email: "test@example.com",
      feature_key: "data_export",
      feature_name: "Data Export",
      context: "dashboard_export"
    )

    assert_equal "dashboard_export", submission.context
  end

  test "inherits from FormSubmission" do
    assert_operator FeatureWaitlistSubmission, :<, FormSubmission
  end

  test "has prefix_id from FormSubmission" do
    assert_respond_to feature_waitlist_data_export, :prefix_id
    assert feature_waitlist_data_export.prefix_id.start_with?("form_")
  end

  test "inherits status enum" do
    assert_respond_to feature_waitlist_data_export, :pending?
    assert_respond_to feature_waitlist_data_export, :contacted?
    assert_respond_to feature_waitlist_data_export, :completed?
    assert_respond_to feature_waitlist_data_export, :spam?
  end

  private

  def feature_waitlist_data_export
    @feature_waitlist_data_export ||= form_submissions(:feature_waitlist_data_export)
  end
end
