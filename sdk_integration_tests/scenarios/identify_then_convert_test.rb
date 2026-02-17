# frozen_string_literal: true

require_relative "../test_helper"

# Phase 4: Tests the identify → convert flow WITHOUT explicit user_id.
# After identify(), the server resolves identity from the visitor link,
# so conversions get identity_id set even without the SDK passing user_id.
class IdentifyThenConvertTest < SdkIntegrationTest
  def test_conversion_has_identity_after_identify
    visit_and_register

    user_id = "itc_#{SecureRandom.hex(6)}"

    # Step 1: Identify the visitor
    within("#identify-form") do
      fill_in "identify-user-id", with: user_id
      fill_in "identify-traits", with: '{"email": "itc@example.com"}'
      click_button "Identify"
    end
    wait_for_async(3)

    # Step 2: Track conversion WITHOUT explicit user_id
    within("#conversion-form") do
      fill_in "conversion-type", with: "itc_purchase"
      fill_in "conversion-revenue", with: "149.99"
      fill_in "conversion-user-id", with: ""
      click_button "Track Conversion"
    end
    wait_for_async(3)

    # Step 3: Verify conversion has identity_id set
    data = verify_test_data
    conversion = data[:conversions].find { |c| c[:conversion_type] == "itc_purchase" }

    assert_not_nil conversion, "Should have itc_purchase conversion"
    assert_equal 149.99, conversion[:revenue].to_f
    assert_not_nil conversion[:identity_id], "Conversion should have identity_id (resolved from visitor)"
  end

  def test_conversion_with_explicit_user_id_still_works
    visit_and_register

    user_id = "itc_explicit_#{SecureRandom.hex(6)}"

    # Identify first
    within("#identify-form") do
      fill_in "identify-user-id", with: user_id
      click_button "Identify"
    end
    wait_for_async(3)

    # Convert WITH explicit user_id (existing behavior)
    within("#conversion-form") do
      fill_in "conversion-type", with: "itc_explicit_purchase"
      fill_in "conversion-revenue", with: "50.00"
      fill_in "conversion-user-id", with: user_id
      click_button "Track Conversion"
    end
    wait_for_async(3)

    data = verify_test_data
    conversion = data[:conversions].find { |c| c[:conversion_type] == "itc_explicit_purchase" }

    assert_not_nil conversion, "Should have itc_explicit_purchase conversion"
    assert_not_nil conversion[:identity_id], "Conversion should have identity_id"
  end
end
