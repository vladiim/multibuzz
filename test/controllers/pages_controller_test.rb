# frozen_string_literal: true

require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  # --- home ---

  test "home renders ad integrations column in pricing table" do
    get root_path

    assert_response :success
    assert_match(/Ad Integrations/, response.body)
  end

  test "home shows per-plan integration counts" do
    get root_path

    assert_match(/>2</, response.body) # Starter
    assert_match(/>5</, response.body) # Growth
    assert_match(/Unlimited/, response.body) # Pro
  end

  # --- pricing ---

  test "pricing page mentions ad platform integrations in hero copy" do
    get pricing_path

    assert_response :success
    assert_match(/Google Ads/, response.body)
    assert_match(/Meta and LinkedIn/, response.body)
  end

  test "pricing page includes ad platforms FAQ" do
    get pricing_path

    assert_match(/Which ad platforms are supported\?/, response.body)
  end

  test "pricing page schema.org mentions integration counts" do
    get pricing_path

    assert_match(/2 ad platform integrations/, response.body)
    assert_match(/5 ad platform integrations/, response.body)
    assert_match(/Unlimited ad platform integrations/, response.body)
  end
end
