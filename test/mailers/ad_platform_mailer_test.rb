# frozen_string_literal: true

require "test_helper"

class AdPlatformMailerTest < ActionMailer::TestCase
  test "api_usage_warning delivers to notification email" do
    assert_equal [ FormSubmissionMailer::NOTIFICATION_EMAIL ], email.to
  end

  test "api_usage_warning subject includes percentage and count" do
    assert_equal "[mbuzz] Google Ads API usage at 85% (12,750/15,000)", email.subject
  end

  test "api_usage_warning body includes current operations" do
    assert_includes email.body.to_s, "12,750"
  end

  test "api_usage_warning body includes remaining operations" do
    assert_includes email.body.to_s, "2,250"
  end

  test "api_usage_warning body includes Basic Access note" do
    assert_includes email.body.to_s, "Basic Access"
  end

  private

  def email
    @email ||= AdPlatformMailer.api_usage_warning(
      operations_today: 12_750,
      limit: 15_000,
      percentage: 85
    )
  end
end
