require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  # --- Show (main onboarding entry point) ---

  test "show requires authentication" do
    get onboarding_path

    assert_redirected_to login_path
  end

  test "show renders persona selection for new users" do
    sign_in

    get onboarding_path

    assert_response :success
    assert_select "[data-onboarding-persona]"
  end

  test "show redirects to setup if persona already selected" do
    sign_in
    account.update!(onboarding_persona: :developer)
    account.complete_onboarding_step!(:persona_selected)

    get onboarding_path

    assert_redirected_to onboarding_setup_path
  end

  # --- Persona ---

  test "persona requires authentication" do
    post onboarding_persona_path, params: { persona: "developer" }

    assert_redirected_to login_path
  end

  test "persona updates account persona and redirects to setup" do
    sign_in_as_new_user

    post onboarding_persona_path, params: { persona: "developer" }

    @test_account.reload
    assert @test_account.developer?
    assert @test_account.onboarding_step_completed?(:persona_selected)
    assert_redirected_to onboarding_setup_path
  end

  test "persona redirects marketer to dashboard with demo data" do
    sign_in_as_new_user

    post onboarding_persona_path, params: { persona: "marketer" }

    @test_account.reload
    assert @test_account.marketer?
    assert_redirected_to dashboard_path
  end

  # --- Setup (API key + SDK selection) ---

  test "setup requires authentication" do
    get onboarding_setup_path

    assert_redirected_to login_path
  end

  test "setup renders API key and SDK selection" do
    sign_in
    account.update!(onboarding_persona: :developer)

    get onboarding_setup_path

    assert_response :success
    assert_select "[data-api-key]"
    assert_select "[data-sdk-grid]"
  end

  test "setup displays live and coming_soon SDKs" do
    sign_in
    account.update!(onboarding_persona: :developer)

    get onboarding_setup_path

    assert_select "[data-sdk-card]", minimum: 2
  end

  # --- SDK Selection ---

  test "select_sdk requires authentication" do
    post onboarding_select_sdk_path, params: { sdk: "ruby" }

    assert_redirected_to login_path
  end

  test "select_sdk saves selected SDK and redirects to install" do
    sign_in_as_new_user

    post onboarding_select_sdk_path, params: { sdk: "ruby" }

    @test_account.reload
    assert_equal "ruby", @test_account.selected_sdk
    assert @test_account.onboarding_step_completed?(:sdk_selected)
    assert_redirected_to onboarding_install_path
  end

  test "select_sdk with coming_soon SDK shows waitlist modal" do
    sign_in

    post onboarding_select_sdk_path, params: { sdk: "python" }

    # Should redirect to waitlist signup for coming soon SDKs
    assert_response :redirect
  end

  # --- Install ---

  test "install requires authentication" do
    get onboarding_install_path

    assert_redirected_to login_path
  end

  test "install renders SDK-specific installation guide" do
    sign_in
    account.update!(selected_sdk: "ruby")

    get onboarding_install_path

    assert_response :success
    assert_select "code", /mbuzz/
  end

  test "install redirects to setup if no SDK selected" do
    sign_in

    get onboarding_install_path

    assert_redirected_to onboarding_setup_path
  end

  # --- Verify ---

  test "verify requires authentication" do
    get onboarding_verify_path

    assert_redirected_to login_path
  end

  test "verify renders waiting state" do
    sign_in
    account.update!(selected_sdk: "ruby")

    get onboarding_verify_path

    assert_response :success
    assert_select "[data-verification]"
  end

  # --- Event Status (polling endpoint) ---

  test "event_status returns received false when no events" do
    sign_in_as_new_user

    get onboarding_event_status_path

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal false, json["received"]
  end

  test "event_status returns received true when events exist" do
    sign_in

    get onboarding_event_status_path

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal true, json["received"]
  end

  # --- Conversion ---

  test "conversion requires authentication" do
    get onboarding_conversion_path

    assert_redirected_to login_path
  end

  test "conversion renders conversion tracking guide" do
    sign_in
    account.update!(selected_sdk: "ruby")

    get onboarding_conversion_path

    assert_response :success
    assert_select "pre", /conversion/
  end

  # --- Attribution (aha moment) ---

  test "attribution requires authentication" do
    get onboarding_attribution_path

    assert_redirected_to login_path
  end

  test "attribution renders attribution visualization" do
    sign_in
    create_test_conversion

    get onboarding_attribution_path

    assert_response :success
    assert_select "[data-model-switcher]"
  end

  # --- Complete ---

  test "complete redirects to dashboard" do
    sign_in
    account.complete_onboarding_step!(:attribution_viewed)

    get onboarding_complete_path

    assert_redirected_to dashboard_path
  end

  private

  def sign_in
    post login_path, params: { email: user.email, password: "password123" }
  end

  def sign_in_as_new_user
    @test_user = User.create!(email: "newuser#{SecureRandom.hex(4)}@example.com", password: "password123")
    @test_account = Account.create!(name: "New Account", slug: "new-account-#{SecureRandom.hex(4)}")
    AccountMembership.create!(user: @test_user, account: @test_account, role: :owner, status: :accepted)
    post login_path, params: { email: @test_user.email, password: "password123" }
  end

  def user
    @user ||= users(:one)
  end

  def account
    @account ||= user.primary_account
  end

  def create_test_event
    visitor = account.visitors.create!(visitor_id: SecureRandom.hex(32))
    session = account.sessions.create!(
      visitor: visitor,
      session_id: SecureRandom.hex(32),
      started_at: Time.current,
      channel: Channels::DIRECT
    )
    account.events.create!(
      event_type: "test_event",
      visitor: visitor,
      session: session,
      occurred_at: Time.current,
      properties: { test: true }
    )
  end

  def create_test_conversion
    visitor = account.visitors.create!(visitor_id: SecureRandom.hex(32))
    account.conversions.create!(
      visitor: visitor,
      conversion_type: "test",
      revenue: 99.99,
      converted_at: Time.current
    )
  end
end
