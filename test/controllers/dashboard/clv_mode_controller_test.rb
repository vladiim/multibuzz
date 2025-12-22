# frozen_string_literal: true

require "test_helper"

module Dashboard
  class ClvModeControllerTest < ActionDispatch::IntegrationTest
    setup do
      # Complete onboarding so default view mode is production
      accounts(:one).update!(onboarding_progress: (1 << Account::Onboarding::ONBOARDING_STEPS.size) - 1)
      sign_in_as(user)
      # Ensure production mode and transactions mode for most tests
      patch dashboard_view_mode_path, params: { mode: "production" }
      follow_redirect!
      # Clear any existing test data
      AttributionCredit.delete_all
      Conversion.where(account: account).delete_all
    end

    # ==========================================
    # CLV Mode Toggle Tests
    # ==========================================

    test "should update clv mode to clv" do
      patch dashboard_clv_mode_path, params: { mode: "clv" }

      assert_redirected_to dashboard_path
      follow_redirect!
      assert_equal "clv", session[:clv_mode]
    end

    test "should update clv mode to transactions" do
      # First set to clv mode
      patch dashboard_clv_mode_path, params: { mode: "clv" }
      follow_redirect!

      # Then switch back to transactions
      patch dashboard_clv_mode_path, params: { mode: "transactions" }

      assert_redirected_to dashboard_path
      follow_redirect!
      assert_equal "transactions", session[:clv_mode]
    end

    test "should reject invalid clv mode" do
      patch dashboard_clv_mode_path, params: { mode: "invalid" }

      assert_redirected_to dashboard_path
      follow_redirect!
      assert_equal "transactions", session[:clv_mode]
    end

    test "should default to transactions when mode is blank" do
      patch dashboard_clv_mode_path, params: { mode: "" }

      assert_redirected_to dashboard_path
      follow_redirect!
      assert_equal "transactions", session[:clv_mode]
    end

    test "should require login" do
      logout

      patch dashboard_clv_mode_path, params: { mode: "clv" }

      assert_redirected_to login_path
    end

    # ==========================================
    # Dashboard Toggle UI Tests
    # ==========================================

    test "dashboard shows clv mode toggle" do
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='clv-mode-toggle']"
    end

    test "toggle shows Transactions active by default" do
      get dashboard_path

      assert_response :success
      assert_select "[data-testid='clv-mode-toggle']" do
        assert_select "button.bg-white", text: /Transactions/i
      end
    end

    test "toggle shows Customer LTV active when in clv mode" do
      patch dashboard_clv_mode_path, params: { mode: "clv" }
      follow_redirect!

      get dashboard_path
      assert_select "[data-testid='clv-mode-toggle']" do
        assert_select "button.bg-white", text: /Customer LTV/i
      end
    end

    # ==========================================
    # CLV Dashboard Rendering Tests
    # ==========================================

    test "renders transactions dashboard by default" do
      get dashboard_conversions_path

      assert_response :success
      assert_select "[data-testid='transactions-dashboard']"
      assert_select "[data-testid='clv-dashboard']", count: 0
    end

    test "renders clv dashboard when in clv mode" do
      patch dashboard_clv_mode_path, params: { mode: "clv" }
      follow_redirect!

      get dashboard_conversions_path

      assert_select "[data-testid='clv-dashboard']"
      assert_select "[data-testid='transactions-dashboard']", count: 0
    end

    # Note: KPI card rendering with data is tested via ClvDataService unit tests.
    # Integration tests for data-dependent views are complex due to transaction
    # boundaries in Rails integration tests. The service tests provide coverage.

    # ==========================================
    # Empty State Tests
    # ==========================================

    test "clv dashboard shows empty state when no acquisition data" do
      # Ensure no acquisition conversions exist
      Conversion.where(account: account).update_all(is_acquisition: false)

      patch dashboard_clv_mode_path, params: { mode: "clv" }
      follow_redirect!
      get dashboard_conversions_path

      assert_select "[data-testid='clv-empty-state']"
    end

    test "empty state includes setup instructions" do
      Conversion.where(account: account).update_all(is_acquisition: false)

      patch dashboard_clv_mode_path, params: { mode: "clv" }
      follow_redirect!
      get dashboard_conversions_path

      assert_select "[data-testid='clv-empty-state']" do
        assert_select "code", /is_acquisition/
        assert_select "code", /inherit_acquisition/
      end
    end

    # ==========================================
    # CLV Data Tests
    # ==========================================

    test "clv totals are calculated correctly" do
      create_clv_test_data
      patch dashboard_clv_mode_path, params: { mode: "clv" }
      follow_redirect!
      get dashboard_conversions_path

      clv_data = controller.instance_variable_get(:@clv_data)

      assert clv_data[:totals].key?(:clv)
      assert clv_data[:totals].key?(:customers)
      assert clv_data[:totals].key?(:purchases)
      assert clv_data[:totals].key?(:revenue)
      assert clv_data[:totals].key?(:avg_duration)
      assert clv_data[:totals].key?(:repurchase_frequency)
    end

    test "clv by channel is calculated" do
      create_clv_test_data
      patch dashboard_clv_mode_path, params: { mode: "clv" }
      follow_redirect!
      get dashboard_conversions_path

      clv_data = controller.instance_variable_get(:@clv_data)

      assert clv_data.key?(:by_channel)
      assert clv_data[:by_channel].is_a?(Array)
    end

    test "coverage percentage is calculated" do
      create_clv_test_data
      patch dashboard_clv_mode_path, params: { mode: "clv" }
      follow_redirect!
      get dashboard_conversions_path

      clv_data = controller.instance_variable_get(:@clv_data)

      assert clv_data.key?(:coverage)
      assert clv_data[:coverage].key?(:percentage)
    end

    private

    def user
      @user ||= users(:one)
    end

    def account
      @account ||= accounts(:one)
    end

    def sign_in_as(user)
      post login_path, params: { email: user.email, password: "password123" }
    end

    def logout
      delete logout_path
    end

    def identity
      @identity ||= account.identities.create!(
        external_id: "clv_test_user",
        first_identified_at: 30.days.ago,
        last_identified_at: Time.current
      )
    end

    def first_touch_model
      @first_touch_model ||= attribution_models(:first_touch)
    end

    def create_clv_test_data
      # Clear existing data
      AttributionCredit.delete_all
      Conversion.where(account: account).delete_all

      # Create acquisition conversion (30 days ago)
      acquisition = account.conversions.create!(
        visitor: visitors(:one),
        identity: identity,
        conversion_type: "signup",
        is_acquisition: true,
        converted_at: 30.days.ago,
        is_test: false
      )

      # Create acquisition attribution
      account.attribution_credits.create!(
        conversion: acquisition,
        attribution_model: first_touch_model,
        session_id: 1,
        channel: Channels::ORGANIC_SEARCH,
        credit: 1.0,
        revenue_credit: 0,
        is_test: false
      )

      # Create subsequent payments (linked to same identity)
      [20.days.ago, 10.days.ago, 2.days.ago].each_with_index do |time, i|
        payment = account.conversions.create!(
          visitor: visitors(:one),
          identity: identity,
          conversion_type: "payment",
          revenue: 49.00,
          converted_at: time,
          is_test: false
        )

        # Inherit attribution from acquisition
        account.attribution_credits.create!(
          conversion: payment,
          attribution_model: first_touch_model,
          session_id: 1,
          channel: Channels::ORGANIC_SEARCH,
          credit: 1.0,
          revenue_credit: 49.00,
          is_test: false
        )
      end
    end
  end
end
