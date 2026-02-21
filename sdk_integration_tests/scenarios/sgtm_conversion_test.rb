# frozen_string_literal: true

require_relative "../test_helper"

# Tests that the sGTM simulation app tracks conversions correctly
# by making direct HTTP calls to the mbuzz conversions API.
class SgtmConversionTest < SdkIntegrationTest
  def test_tracks_conversion_with_revenue
    visit_and_register

    within("#conversion-form") do
      fill_in "conversion-type", with: "purchase"
      fill_in "conversion-revenue", with: "149.99"
      fill_in "conversion-properties", with: '{"orderId": "ORD-SGTM-001"}'
      click_button "Track Conversion"
    end

    wait_for_async(3)

    data = verify_test_data

    assert_not_nil data[:conversions], "Should have conversions"
    assert data[:conversions].any? { |c| c[:conversion_type] == "purchase" },
      "Should have purchase conversion"

    conversion = data[:conversions].find { |c| c[:conversion_type] == "purchase" }

    assert_equal "149.99", conversion[:revenue].to_s
  end
end
