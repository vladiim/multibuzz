# frozen_string_literal: true

require_relative "../test_helper"

class IdentifyTest < SdkIntegrationTest
  def test_identifies_user_via_ui
    # Register visitor first
    visit_and_register

    # Fill in identify form using unique IDs
    within("#identify-form") do
      fill_in "identify-user-id", with: "test_user_#{SecureRandom.hex(4)}"
      fill_in "identify-traits", with: '{"email": "test@example.com", "name": "Test User"}'
      click_button "Identify"
    end

    # Wait for async processing
    wait_for_async(3)

    # Verify identity in database
    data = verify_test_data
    assert_not_nil data[:identity], "Should have identity"
    assert_equal "test@example.com", data[:identity][:traits][:email]
    assert_equal "Test User", data[:identity][:traits][:name]
  end

  def test_links_visitor_to_identity
    # Register visitor first
    visit_and_register

    user_id = "link_test_#{SecureRandom.hex(4)}"
    within("#identify-form") do
      fill_in "identify-user-id", with: user_id
      fill_in "identify-traits", with: '{"email": "link@example.com"}'
      click_button "Identify"
    end

    wait_for_async(3)

    data = verify_test_data

    # Visitor should be linked to identity
    assert_not_nil data[:visitor][:identity_id], "Visitor should have identity_id"
    assert_not_nil data[:identity], "Identity should exist"
    assert_equal user_id, data[:identity][:user_id]
  end

  def test_updates_traits_on_re_identify
    # Register visitor first
    visit_and_register

    user_id = "update_test_#{SecureRandom.hex(4)}"

    within("#identify-form") do
      # First identify
      fill_in "identify-user-id", with: user_id
      fill_in "identify-traits", with: '{"email": "first@example.com"}'
      click_button "Identify"
    end
    wait_for_async(2)

    within("#identify-form") do
      # Second identify with updated traits
      fill_in "identify-traits", with: '{"email": "updated@example.com", "plan": "pro"}'
      click_button "Identify"
    end
    wait_for_async(3)

    data = verify_test_data
    assert_equal "updated@example.com", data[:identity][:traits][:email]
    assert_equal "pro", data[:identity][:traits][:plan]
  end
end
