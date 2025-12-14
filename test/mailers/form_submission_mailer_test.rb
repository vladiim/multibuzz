# frozen_string_literal: true

require "test_helper"

class FormSubmissionMailerTest < ActionMailer::TestCase
  test "notify sends to configured recipient" do
    email = FormSubmissionMailer.notify(contact_submission)

    assert_emails 1 do
      email.deliver_now
    end

    assert_equal ["vlad@forebrite.com"], email.to
  end

  test "notify contact submission has correct subject" do
    email = FormSubmissionMailer.notify(contact_submission)

    assert_match(/Contact/, email.subject)
    assert_match(/general/, email.subject)
    assert_match(/Jane Doe/, email.subject)
  end

  test "notify contact submission includes message in body" do
    email = FormSubmissionMailer.notify(contact_submission)

    assert_match(/Jane Doe/, email.body.encoded)
    assert_match(/jane@example.com/, email.body.encoded)
    assert_match(/general question/, email.body.encoded)
  end

  test "notify waitlist submission has correct subject" do
    email = FormSubmissionMailer.notify(waitlist_submission)

    assert_match(/Waitlist/, email.subject)
    assert_match(/developer@example.com/, email.subject)
  end

  test "notify waitlist submission includes details in body" do
    email = FormSubmissionMailer.notify(waitlist_submission)

    assert_match(/developer@example.com/, email.body.encoded)
    assert_match(/developer/, email.body.encoded)
    assert_match(/rails/, email.body.encoded)
  end

  test "notify feature waitlist submission has correct subject" do
    email = FormSubmissionMailer.notify(feature_waitlist_submission)

    assert_match(/Feature Waitlist/, email.subject)
    assert_match(/Data Export/, email.subject)
  end

  test "notify feature waitlist submission includes details in body" do
    email = FormSubmissionMailer.notify(feature_waitlist_submission)

    assert_match(/export@example.com/, email.body.encoded)
    assert_match(/Data Export/, email.body.encoded)
    assert_match(/data_export/, email.body.encoded)
  end

  test "notify from address is correct" do
    email = FormSubmissionMailer.notify(contact_submission)

    assert_equal ["hello@mbuzz.co"], email.from
  end

  private

  def contact_submission
    @contact_submission ||= form_submissions(:contact_general)
  end

  def waitlist_submission
    @waitlist_submission ||= form_submissions(:waitlist_one)
  end

  def feature_waitlist_submission
    @feature_waitlist_submission ||= form_submissions(:feature_waitlist_data_export)
  end
end
