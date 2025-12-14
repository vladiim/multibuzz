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

  test "setup creates API key if none exists" do
    sign_in_as_new_user

    assert_difference -> { @test_account.api_keys.count }, 1 do
      get onboarding_setup_path
    end

    assert @test_account.api_keys.test.exists?
  end

  test "setup shows plaintext key only on first view then clears it" do
    sign_in_as_new_user

    # First view - plaintext shown (dark bg, green text)
    get onboarding_setup_path
    assert_nil session[:plaintext_api_key], "Session should be cleared after first view"
    assert_select "code.text-green-400", /sk_test_/

    # Second view - masked key shown (gray bg)
    get onboarding_setup_path
    assert_select "code.text-gray-500", /sk_test_.*••••/
  end

  test "setup does not regenerate key for existing key" do
    sign_in

    assert_no_difference -> { account.api_keys.count } do
      get onboarding_setup_path
    end

    # Shows masked key (gray bg) because key already existed
    assert_select "code.text-gray-500", /sk_test_.*••••/
  end

  test "setup displays live and coming_soon SDKs" do
    sign_in
    account.update!(onboarding_persona: :developer)

    get onboarding_setup_path

    assert_select "[data-sdk-card]", minimum: 2
  end

  # --- Regenerate API Key ---

  test "regenerate_api_key revokes old key and creates new one" do
    sign_in
    old_key = account.api_keys.test.active.first

    post onboarding_regenerate_api_key_path

    assert_redirected_to onboarding_setup_path
    assert old_key.reload.revoked?
    assert session[:plaintext_api_key].present?
    assert session[:plaintext_api_key].start_with?("sk_test_")
  end

  test "regenerate_api_key requires authentication" do
    post onboarding_regenerate_api_key_path

    assert_redirected_to login_path
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

  test "select_sdk with coming_soon SDK still saves selection" do
    sign_in_as_new_user

    post onboarding_select_sdk_path, params: { sdk: "python" }

    @test_account.reload
    assert_equal "python", @test_account.selected_sdk
    assert_redirected_to onboarding_install_path
  end

  # --- Waitlist SDK ---

  test "waitlist_sdk requires authentication" do
    post onboarding_waitlist_sdk_path, params: { sdk: "python" }

    assert_redirected_to login_path
  end

  test "waitlist_sdk creates submission and redirects back with notice" do
    sign_in

    assert_difference "SdkWaitlistSubmission.count", 1 do
      post onboarding_waitlist_sdk_path, params: { sdk: "python" }
    end

    assert_redirected_to onboarding_setup_path
    assert flash[:notice].include?("waitlist")

    submission = SdkWaitlistSubmission.last
    assert_equal "python", submission.sdk_key
    assert_equal user.email, submission.email
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

  test "verify redirects to conversion if first_event_received already completed" do
    sign_in
    account.update!(selected_sdk: "ruby")
    account.complete_onboarding_step!(:first_event_received)

    get onboarding_verify_path

    assert_redirected_to onboarding_conversion_path
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

  test "conversion redirects to attribution if first_conversion already completed" do
    sign_in
    account.update!(selected_sdk: "ruby")
    account.complete_onboarding_step!(:first_conversion)

    get onboarding_conversion_path

    assert_redirected_to onboarding_attribution_path
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
