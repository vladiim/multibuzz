# frozen_string_literal: true

require "test_helper"

# Unit-tests the `skip_marketing_analytics` class-level opt-out and the
# `marketing_analytics_enabled?` helper exposed by ApplicationController.
# Integration tests that confirm the GTM mount is suppressed live in the
# layout sweep test once GTM partials exist.
class MarketingAnalyticsEnabledTest < ActiveSupport::TestCase
  EnabledController = Class.new(ApplicationController)
  SkippedController = Class.new(ApplicationController) { skip_marketing_analytics }

  test "skip_marketing_analytics flips the class flag on the declaring class only" do
    assert SkippedController.marketing_analytics_skipped
    refute EnabledController.marketing_analytics_skipped
    refute ApplicationController.marketing_analytics_skipped
  end

  test "marketing_analytics_enabled? returns true on a normal controller and root path" do
    assert enabled_for(EnabledController, "/")
  end

  test "marketing_analytics_enabled? returns true on a normal controller and dashboard path" do
    assert enabled_for(EnabledController, "/dashboard")
  end

  test "marketing_analytics_enabled? returns false when controller skips" do
    refute enabled_for(SkippedController, "/")
  end

  test "marketing_analytics_enabled? returns false on admin path" do
    refute enabled_for(EnabledController, "/admin/accounts")
  end

  test "marketing_analytics_enabled? returns false on api keys path" do
    refute enabled_for(EnabledController, "/accounts/acct_abc/api_keys")
  end

  test "marketing_analytics_enabled? returns false on onboarding install path" do
    refute enabled_for(EnabledController, "/onboarding/install")
  end

  test "marketing_analytics_enabled? returns false on identity show path" do
    refute enabled_for(EnabledController, "/dashboard/identities/idt_abc12345")
  end

  test "marketing_analytics_enabled? returns false on path with api key literal" do
    refute enabled_for(EnabledController, "/anything?key=sk_live_xyz")
  end

  private

  def enabled_for(controller_class, path)
    controller_class.new.tap { |c| c.request = stub_request(path) }.send(:marketing_analytics_enabled?)
  end

  def stub_request(path)
    ActionDispatch::TestRequest.create("PATH_INFO" => path)
  end
end
