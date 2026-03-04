# frozen_string_literal: true

require "test_helper"

class IntegrationRequest::CreateServiceTest < ActiveSupport::TestCase
  test "creates submission for valid platform" do
    result = service.call

    assert result[:success]
    assert_equal "Meta Ads", result[:submission].platform_name
    assert_equal user.email, result[:submission].email
  end

  test "stores account context" do
    result = service.call

    assert_equal account.prefix_id, result[:submission].account_id
  end

  test "returns error for duplicate request" do
    IntegrationRequestSubmission.create!(email: user.email, platform_name: "Meta Ads")

    result = service.call

    refute result[:success]
    assert_includes result[:errors].first, "already requested"
  end

  test "allows same platform from different users" do
    IntegrationRequestSubmission.create!(email: "other@example.com", platform_name: "Meta Ads")

    result = service.call

    assert result[:success]
  end

  test "creates submission with notes and monthly_spend" do
    result = service(platform_name: "Other", platform_name_other: "Spotify Ads",
                     monthly_spend: "$1K – $10K", notes: "We need this").call

    assert_equal "Spotify Ads", result[:submission].platform_name_other
    assert_equal "$1K – $10K", result[:submission].monthly_spend
    assert_equal "We need this", result[:submission].notes
  end

  test "anonymizes IP address" do
    result = service.call

    assert_predicate result[:submission].ip_address, :present?
  end

  private

  def service(overrides = {})
    params = ActionController::Parameters.new({
      platform_name: "Meta Ads"
    }.merge(overrides))

    IntegrationRequest::CreateService.new(
      user: user, account: account,
      params: params, request: mock_request
    )
  end

  def user = @user ||= users(:one)
  def account = @account ||= accounts(:one)

  def mock_request
    @mock_request ||= OpenStruct.new(remote_ip: "192.168.1.100", user_agent: "TestAgent/1.0")
  end
end
