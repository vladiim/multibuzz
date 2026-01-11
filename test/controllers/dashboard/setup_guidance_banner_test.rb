# frozen_string_literal: true

require "test_helper"

module Dashboard
  class SetupGuidanceBannerTest < ActionDispatch::IntegrationTest
    setup do
      # Enable live mode so default view mode is production
      account.update!(live_mode_enabled: true)
      # Clear any existing data
      account.api_keys.destroy_all
      account.events.destroy_all
      account.conversions.destroy_all
      account.identities.destroy_all
    end

    # ==========================================
    # No Live API Key Banner
    # ==========================================

    test "shows no live API key banner when account has no live keys" do
      sign_in_as(user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='setup-banner-api-key']"
      assert_select "[data-testid='setup-banner-api-key']", text: /Generate a live API key/
    end

    test "hides API key banner when account has live key" do
      ApiKeys::GenerationService.new(account, environment: :live).call
      sign_in_as(user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='setup-banner-api-key']", count: 0
    end

    # ==========================================
    # No Events Banner (requires live key first)
    # ==========================================

    test "shows no events banner when account has live key but no production events" do
      ApiKeys::GenerationService.new(account, environment: :live).call
      sign_in_as(user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='setup-banner-events']"
      assert_select "[data-testid='setup-banner-events']", text: /Track your first event/
    end

    test "hides events banner when account has production events" do
      ApiKeys::GenerationService.new(account, environment: :live).call
      create_production_event
      sign_in_as(user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='setup-banner-events']", count: 0
    end

    # ==========================================
    # No Conversions Banner (requires events first)
    # ==========================================

    test "shows no conversions banner when account has events but no production conversions" do
      ApiKeys::GenerationService.new(account, environment: :live).call
      create_production_event
      sign_in_as(user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='setup-banner-conversions']"
      assert_select "[data-testid='setup-banner-conversions']", text: /Track conversions/
    end

    test "hides conversions banner when account has production conversions" do
      ApiKeys::GenerationService.new(account, environment: :live).call
      create_production_event
      create_production_conversion
      sign_in_as(user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='setup-banner-conversions']", count: 0
    end

    # ==========================================
    # No Users Banner (requires conversions first)
    # ==========================================

    test "shows no users banner when account has conversions but no production identities" do
      ApiKeys::GenerationService.new(account, environment: :live).call
      create_production_event
      create_production_conversion
      sign_in_as(user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='setup-banner-users']"
      assert_select "[data-testid='setup-banner-users']", text: /Identify users/
    end

    test "hides users banner when account has production identities" do
      ApiKeys::GenerationService.new(account, environment: :live).call
      create_production_event
      create_production_conversion
      create_production_identity
      sign_in_as(user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='setup-banner-users']", count: 0
    end

    # ==========================================
    # Test mode hides all setup banners
    # ==========================================

    test "hides all setup banners in test mode" do
      # Disable live mode so default is test mode
      account.update!(live_mode_enabled: false)
      sign_in_as(user)
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='setup-banner-api-key']", count: 0
      assert_select "[data-testid='setup-banner-events']", count: 0
      assert_select "[data-testid='setup-banner-conversions']", count: 0
      assert_select "[data-testid='setup-banner-users']", count: 0
    end

    # ==========================================
    # Priority: Only show one banner at a time
    # ==========================================

    test "only shows highest priority banner" do
      ApiKeys::GenerationService.new(account, environment: :live).call
      sign_in_as(user)
      get dashboard_path

      assert_response :success
      # Should show events banner (next step after API key)
      assert_select "[data-testid='setup-banner-events']"
      # Should NOT show conversions or users banners yet
      assert_select "[data-testid='setup-banner-conversions']", count: 0
      assert_select "[data-testid='setup-banner-users']", count: 0
    end

    private

    def user
      @user ||= users(:three) # User with single account membership
    end

    def account
      @account ||= accounts(:one)
    end

    def sign_in_as(user)
      post login_path, params: { email: user.email, password: "password123" }
    end

    def create_production_event
      visitor = account.visitors.create!(visitor_id: SecureRandom.uuid, is_test: false)
      session = account.sessions.create!(
        visitor: visitor,
        session_id: SecureRandom.uuid,
        started_at: Time.current,
        is_test: false
      )
      account.events.create!(
        visitor: visitor,
        session: session,
        event_type: "page_view",
        occurred_at: Time.current,
        is_test: false,
        properties: { url: "https://example.com" }
      )
    end

    def create_production_conversion
      visitor = account.visitors.production.first || create_production_visitor
      account.conversions.create!(
        visitor: visitor,
        conversion_type: "purchase",
        converted_at: Time.current,
        is_test: false
      )
    end

    def create_production_identity
      account.identities.create!(
        external_id: "user_123",
        is_test: false,
        first_identified_at: Time.current,
        last_identified_at: Time.current
      )
    end

    def create_production_visitor
      account.visitors.create!(visitor_id: SecureRandom.uuid, is_test: false)
    end
  end
end
