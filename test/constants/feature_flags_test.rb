# frozen_string_literal: true

require "test_helper"

class FeatureFlagsTest < ActiveSupport::TestCase
  test "ALL contains every defined flag" do
    expected = [
      FeatureFlags::GOOGLE_ADS_INTEGRATION,
      FeatureFlags::META_ADS_INTEGRATION,
      FeatureFlags::LINKEDIN_ADS_INTEGRATION,
      FeatureFlags::CONVERSION_FEEDBACK
    ]

    assert_equal expected.sort, FeatureFlags::ALL.sort
  end

  test "CONVERSION_FEEDBACK is the canonical string" do
    assert_equal "conversion_feedback", FeatureFlags::CONVERSION_FEEDBACK
  end
end
