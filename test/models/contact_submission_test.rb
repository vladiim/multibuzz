require "test_helper"

class ContactSubmissionTest < ActiveSupport::TestCase
  test "should have valid fixtures" do
    assert contact_general.valid?
    assert contact_support.valid?
  end

  test "should require name" do
    submission = ContactSubmission.new(
      email: "test@example.com",
      subject: "general",
      message: "Hello"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:name], "can't be blank"
  end

  test "should require subject" do
    submission = ContactSubmission.new(
      email: "test@example.com",
      name: "Test User",
      message: "Hello"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:subject], "can't be blank"
  end

  test "should validate subject inclusion" do
    submission = ContactSubmission.new(
      email: "test@example.com",
      name: "Test User",
      subject: "invalid_subject",
      message: "Hello"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:subject], "invalid_subject is not a valid subject"
  end

  test "should require message" do
    submission = ContactSubmission.new(
      email: "test@example.com",
      name: "Test User",
      subject: "general"
    )

    assert_not submission.valid?
    assert_includes submission.errors[:message], "can't be blank"
  end

  test "should create valid contact submission" do
    submission = ContactSubmission.new(
      email: "new@example.com",
      name: "New User",
      subject: "sales",
      message: "I have a question about pricing."
    )

    assert submission.valid?
    assert submission.save
    assert_equal "ContactSubmission", submission.type
    assert submission.pending?
  end

  test "should access store_accessor fields" do
    assert_equal "Jane Doe", contact_general.name
    assert_equal "general", contact_general.subject
    assert_equal "I have a general question.", contact_general.message
  end

  test "should set store_accessor fields" do
    submission = ContactSubmission.new(email: "test@example.com")

    submission.name = "John Smith"
    submission.subject = "partnership"
    submission.message = "Let's collaborate!"

    assert_equal "John Smith", submission.name
    assert_equal "partnership", submission.subject
    assert_equal "Let's collaborate!", submission.message
    assert_equal "John Smith", submission.data["name"]
    assert_equal "partnership", submission.data["subject"]
    assert_equal "Let's collaborate!", submission.data["message"]
  end

  private

  def contact_general
    @contact_general ||= form_submissions(:contact_general)
  end

  def contact_support
    @contact_support ||= form_submissions(:contact_support)
  end
end
