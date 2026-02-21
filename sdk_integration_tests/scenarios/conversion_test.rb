# frozen_string_literal: true

require_relative "../test_helper"

class ConversionTest < SdkIntegrationTest
  def test_tracks_conversion_via_ui
    # Register visitor first
    visit_and_register

    # Fill in conversion form using unique IDs
    within("#conversion-form") do
      fill_in "conversion-type", with: "test_purchase"
      fill_in "conversion-revenue", with: "99.99"
      fill_in "conversion-properties", with: '{"order_id": "ORD-123"}'
      click_button "Track Conversion"
    end

    # Wait for async processing
    wait_for_async(3)

    # Verify conversion in database
    data = verify_test_data

    assert_not_nil data[:conversions], "Should have conversions"
    assert data[:conversions].any? { |c| c[:conversion_type] == "test_purchase" },
      "Should have test_purchase conversion"

    conversion = data[:conversions].find { |c| c[:conversion_type] == "test_purchase" }

    assert_in_delta(99.99, conversion[:revenue].to_f)
  end

  def test_tracks_acquisition_conversion
    # Register visitor first
    visit_and_register

    # First identify
    user_id = "acq_test_#{SecureRandom.hex(4)}"
    within("#identify-form") do
      fill_in "identify-user-id", with: user_id
      click_button "Identify"
    end
    wait_for_async(2)

    # Then track acquisition conversion
    within("#conversion-form") do
      fill_in "conversion-type", with: "signup"
      fill_in "conversion-user-id", with: user_id
      check "conversion-is-acquisition"
      click_button "Track Conversion"
    end

    wait_for_async(3)

    data = verify_test_data
    conversion = data[:conversions].find { |c| c[:conversion_type] == "signup" }

    assert_not_nil conversion, "Should have signup conversion"
    assert conversion[:is_acquisition], "Should be marked as acquisition"
  end

  def test_tracks_conversion_with_zero_revenue
    # Register visitor first
    visit_and_register

    within("#conversion-form") do
      fill_in "conversion-type", with: "free_signup"
      fill_in "conversion-revenue", with: "0"
      click_button "Track Conversion"
    end

    wait_for_async(3)

    data = verify_test_data
    conversion = data[:conversions].find { |c| c[:conversion_type] == "free_signup" }

    assert_not_nil conversion, "Should have free_signup conversion"
    assert_equal 0, conversion[:revenue].to_i
  end
end
