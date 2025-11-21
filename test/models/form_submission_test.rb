require "test_helper"

class FormSubmissionTest < ActiveSupport::TestCase
  test "should have valid fixtures" do
    assert waitlist_one.valid?
    assert waitlist_two.valid?
  end

  test "should require email" do
    submission = WaitlistSubmission.new(
      role: "developer",
      framework: "rails"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:email], "can't be blank"
  end

  test "should validate email format" do
    submission = WaitlistSubmission.new(
      email: "invalid-email",
      role: "developer",
      framework: "rails"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:email], "must be a valid email address"
  end

  test "should have status enum" do
    assert_equal 0, waitlist_one.status_before_type_cast
    assert waitlist_one.pending?

    waitlist_one.contacted!
    assert waitlist_one.contacted?
    assert_equal 1, waitlist_one.status_before_type_cast
  end

  test "should scope by type" do
    waitlist_submissions = FormSubmission.by_type("WaitlistSubmission")

    assert_includes waitlist_submissions, waitlist_one
    assert_includes waitlist_submissions, waitlist_two
  end

  test "should order by recent" do
    recent = FormSubmission.recent.first

    assert_equal waitlist_other_framework, recent
  end

  test "should store data as jsonb" do
    assert_equal "developer", waitlist_one.data["role"]
    assert_equal "rails", waitlist_one.data["framework"]
  end

  private

  def waitlist_one
    @waitlist_one ||= form_submissions(:waitlist_one)
  end

  def waitlist_two
    @waitlist_two ||= form_submissions(:waitlist_two)
  end

  def waitlist_other_framework
    @waitlist_other_framework ||= form_submissions(:waitlist_other_framework)
  end
end
