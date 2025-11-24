require "test_helper"

class WaitlistControllerTest < ActionDispatch::IntegrationTest
  test "GET new should render new template" do
    get new_waitlist_path

    assert_response :success
  end

  test "POST create with valid params should create submission" do
    assert_difference("WaitlistSubmission.count", 1) do
      post waitlist_index_path, params: valid_params
    end

    assert_redirected_to waitlist_path(WaitlistSubmission.last)
    assert_equal "Thanks for joining the waitlist! We'll be in touch soon.", flash[:notice]
  end

  test "POST create should capture IP address" do
    post waitlist_index_path, params: valid_params

    submission = WaitlistSubmission.last
    assert_not_nil submission.ip_address
  end

  test "POST create should capture user agent" do
    post waitlist_index_path, params: valid_params, headers: { "HTTP_USER_AGENT" => "Test Browser" }

    submission = WaitlistSubmission.last
    assert_equal "Test Browser", submission.user_agent
  end

  test "POST create with invalid email should render new with errors" do
    assert_no_difference("WaitlistSubmission.count") do
      post waitlist_index_path, params: invalid_email_params
    end

    assert_response :unprocessable_entity
  end

  test "POST create with missing role should render new with errors" do
    assert_no_difference("WaitlistSubmission.count") do
      post waitlist_index_path, params: missing_role_params
    end

    assert_response :unprocessable_entity
  end

  test "POST create with invalid framework should render new with errors" do
    assert_no_difference("WaitlistSubmission.count") do
      post waitlist_index_path, params: invalid_framework_params
    end

    assert_response :unprocessable_entity
  end

  test "POST create with framework other requires framework_other field" do
    assert_no_difference("WaitlistSubmission.count") do
      post waitlist_index_path, params: framework_other_missing_params
    end

    assert_response :unprocessable_entity
  end

  test "GET show displays thank you page" do
    submission = create_submission

    get waitlist_path(submission)

    assert_response :success
  end

  private

  def valid_params
    {
      waitlist_submission: {
        email: "test@example.com",
        role: "developer",
        framework: "rails"
      }
    }
  end

  def invalid_email_params
    {
      waitlist_submission: {
        email: "invalid-email",
        role: "developer",
        framework: "rails"
      }
    }
  end

  def missing_role_params
    {
      waitlist_submission: {
        email: "test@example.com",
        framework: "rails"
      }
    }
  end

  def invalid_framework_params
    {
      waitlist_submission: {
        email: "test@example.com",
        role: "developer",
        framework: "invalid"
      }
    }
  end

  def framework_other_missing_params
    {
      waitlist_submission: {
        email: "test@example.com",
        role: "developer",
        framework: "other"
      }
    }
  end

  def create_submission
    WaitlistSubmission.create!(
      email: "test@example.com",
      role: "developer",
      framework: "rails"
    )
  end
end
