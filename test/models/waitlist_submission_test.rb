require "test_helper"

class WaitlistSubmissionTest < ActiveSupport::TestCase
  test "should have valid fixtures" do
    assert waitlist_one.valid?
    assert waitlist_other_framework.valid?
  end

  test "should require role" do
    submission = WaitlistSubmission.new(
      email: "test@example.com",
      framework: "rails"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:role], "can't be blank"
  end

  test "should validate role inclusion" do
    submission = WaitlistSubmission.new(
      email: "test@example.com",
      role: "invalid_role",
      framework: "rails"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:role], "invalid_role is not a valid role"
  end

  test "should require framework" do
    submission = WaitlistSubmission.new(
      email: "test@example.com",
      role: "developer"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:framework], "can't be blank"
  end

  test "should validate framework inclusion" do
    submission = WaitlistSubmission.new(
      email: "test@example.com",
      role: "developer",
      framework: "invalid_framework"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:framework], "invalid_framework is not a valid framework"
  end

  test "should require framework_other when framework is other" do
    submission = WaitlistSubmission.new(
      email: "test@example.com",
      role: "developer",
      framework: "other"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:framework_other], "can't be blank"
  end

  test "should not require framework_other when framework is not other" do
    submission = WaitlistSubmission.new(
      email: "test@example.com",
      role: "developer",
      framework: "rails"
    )

    assert submission.valid?
  end

  test "should create valid waitlist submission" do
    submission = WaitlistSubmission.new(
      email: "new@example.com",
      role: "founder",
      framework: "django"
    )

    assert submission.valid?
    assert submission.save
    assert_equal "WaitlistSubmission", submission.type
    assert submission.pending?
  end

  test "should access store_accessor fields" do
    assert_equal "developer", waitlist_one.role
    assert_equal "rails", waitlist_one.framework
    assert_nil waitlist_one.framework_other

    assert_equal "nextjs", waitlist_other_framework.framework_other
  end

  test "should set store_accessor fields" do
    submission = WaitlistSubmission.new(email: "test@example.com")

    submission.role = "product_manager"
    submission.framework = "laravel"

    assert_equal "product_manager", submission.role
    assert_equal "laravel", submission.framework
    assert_equal "product_manager", submission.data["role"]
    assert_equal "laravel", submission.data["framework"]
  end

  private

  def waitlist_one
    @waitlist_one ||= form_submissions(:waitlist_one)
  end

  def waitlist_other_framework
    @waitlist_other_framework ||= form_submissions(:waitlist_other_framework)
  end
end
