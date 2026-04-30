# frozen_string_literal: true

require "test_helper"

class AdPlatformMailerTest < ActionMailer::TestCase
  test "api_usage_warning delivers to notification email" do
    assert_equal [ FormSubmissionMailer::NOTIFICATION_EMAIL ], google_email.to
  end

  test "api_usage_warning subject includes platform name, percentage and count" do
    assert_equal "[mbuzz] Google Ads API usage at 85% (12,750/15,000)", google_email.subject
  end

  test "api_usage_warning subject reflects platform name when called for Meta Ads" do
    email = AdPlatformMailer.api_usage_warning(
      platform_name: "Meta Ads",
      operations_today: 170_000,
      limit: 200_000,
      percentage: 85
    )

    assert_equal "[mbuzz] Meta Ads API usage at 85% (170,000/200,000)", email.subject
  end

  test "api_usage_warning body includes current operations" do
    assert_includes google_email.body.to_s, "12,750"
  end

  test "api_usage_warning body includes remaining operations" do
    assert_includes google_email.body.to_s, "2,250"
  end

  test "api_usage_warning body includes the platform name" do
    assert_includes google_email.body.to_s, "Google Ads"
  end

  private

  def google_email
    @google_email ||= AdPlatformMailer.api_usage_warning(
      platform_name: "Google Ads",
      operations_today: 12_750,
      limit: 15_000,
      percentage: 85
    )
  end
end
