# frozen_string_literal: true

require "test_helper"

class ContactsControllerTest < ActionDispatch::IntegrationTest
  test "GET new should render new template" do
    get contact_path

    assert_response :success
  end

  test "POST create with valid params should create submission" do
    assert_difference("ContactSubmission.count", 1) do
      post contact_path, params: valid_params
    end

    assert_redirected_to contact_thank_you_path
    assert_equal "Thanks for reaching out! We'll get back to you soon.", flash[:notice]
  end

  test "POST create should capture IP address" do
    post contact_path, params: valid_params

    submission = ContactSubmission.last

    assert_not_nil submission.ip_address
  end

  test "POST create should capture user agent" do
    post contact_path, params: valid_params, headers: { "HTTP_USER_AGENT" => "Test Browser" }

    submission = ContactSubmission.last

    assert_equal "Test Browser", submission.user_agent
  end

  test "POST create with invalid email should render new with errors" do
    assert_no_difference("ContactSubmission.count") do
      post contact_path, params: invalid_email_params
    end

    assert_response :unprocessable_entity
  end

  test "POST create with missing name should render new with errors" do
    assert_no_difference("ContactSubmission.count") do
      post contact_path, params: missing_name_params
    end

    assert_response :unprocessable_entity
  end

  test "POST create with invalid subject should render new with errors" do
    assert_no_difference("ContactSubmission.count") do
      post contact_path, params: invalid_subject_params
    end

    assert_response :unprocessable_entity
  end

  test "POST create with missing message should render new with errors" do
    assert_no_difference("ContactSubmission.count") do
      post contact_path, params: missing_message_params
    end

    assert_response :unprocessable_entity
  end

  test "GET show displays thank you page" do
    get contact_thank_you_path

    assert_response :success
  end

  private

  def valid_params
    {
      contact_submission: {
        email: "test@example.com",
        name: "Test User",
        subject: "general",
        message: "This is a test message."
      }
    }
  end

  def invalid_email_params
    {
      contact_submission: {
        email: "invalid-email",
        name: "Test User",
        subject: "general",
        message: "This is a test message."
      }
    }
  end

  def missing_name_params
    {
      contact_submission: {
        email: "test@example.com",
        subject: "general",
        message: "This is a test message."
      }
    }
  end

  def invalid_subject_params
    {
      contact_submission: {
        email: "test@example.com",
        name: "Test User",
        subject: "invalid",
        message: "This is a test message."
      }
    }
  end

  def missing_message_params
    {
      contact_submission: {
        email: "test@example.com",
        name: "Test User",
        subject: "general"
      }
    }
  end
end
