# frozen_string_literal: true

require "test_helper"

class OnboardingControllerTest < ActionDispatch::IntegrationTest
  # --- Show (setup-choice screen) ---

  test "show requires authentication" do
    get onboarding_path

    assert_redirected_to login_path
  end

  test "show renders the setup-choice screen for new users" do
    sign_in

    get onboarding_path

    assert_response :success
    assert_select "[data-testid='setup-choice']"
  end

  test "show redirects forward when a setup path is already chosen" do
    sign_in
    account.update!(setup_path: :self_serve)

    get onboarding_path

    assert_redirected_to onboarding_setup_path
  end

  # --- Choose path ---

  test "choose_path requires authentication" do
    post onboarding_choose_path_path, params: { setup_path: "self_serve" }

    assert_redirected_to login_path
  end

  test "choose_path stores the path and routes self-serve to setup" do
    sign_in_as_new_user

    post onboarding_choose_path_path, params: { setup_path: "self_serve" }

    @test_account.reload

    assert_predicate @test_account, :self_serve?
    assert @test_account.onboarding_step_completed?(:persona_selected)
    assert_redirected_to onboarding_setup_path
  end

  test "choose_path routes the assisted path to discovery" do
    sign_in_as_new_user

    post onboarding_choose_path_path, params: { setup_path: "assisted" }

    assert_redirected_to onboarding_discovery_path
  end

  test "choose_path routes the teammate path to the in-onboarding invite step" do
    sign_in_as_new_user

    post onboarding_choose_path_path, params: { setup_path: "teammate" }

    assert_redirected_to onboarding_invite_teammate_path
  end

  # --- Change setup path ---

  test "change_setup_path requires authentication" do
    delete onboarding_change_setup_path_path

    assert_redirected_to login_path
  end

  test "change_setup_path clears the chosen path and returns to the choice screen" do
    sign_in
    account.update!(setup_path: :self_serve)

    delete onboarding_change_setup_path_path

    assert_nil account.reload.setup_path
    assert_redirected_to onboarding_path
  end

  # --- Invite Teammate ("A teammate will" path) ---

  test "invite_teammate requires authentication" do
    get onboarding_invite_teammate_path

    assert_redirected_to login_path
  end

  test "invite_teammate redirects accounts not on the teammate path" do
    sign_in
    account.update!(setup_path: :self_serve)

    get onboarding_invite_teammate_path

    assert_redirected_to onboarding_path
  end

  test "invite_teammate renders the invite form within the onboarding chrome" do
    sign_in
    account.update!(setup_path: :teammate)

    get onboarding_invite_teammate_path

    assert_response :success
    assert_select "[data-testid='teammate-invite-form']"
  end

  test "send_teammate_invite creates a pending membership and re-renders with success" do
    sign_in
    account.update!(setup_path: :teammate)

    assert_difference -> { account.account_memberships.pending.count }, 1 do
      post onboarding_send_teammate_invite_path, params: { email: "newdev@example.com", role: "admin" }
    end

    assert_response :success
    assert_select "[data-testid='teammate-invite-sent']", /newdev@example\.com/
  end

  test "send_teammate_invite re-renders with an alert on a service error" do
    sign_in
    account.update!(setup_path: :teammate)

    post onboarding_send_teammate_invite_path, params: { email: "not-an-email", role: "admin" }

    assert_response :success
    assert_select "[data-testid='teammate-invite-form']"
    assert_select ".text-red-700", /invalid/i
  end

  # --- Discovery ---

  test "discovery requires authentication" do
    get onboarding_discovery_path

    assert_redirected_to login_path
  end

  test "discovery renders the form for an assisted account" do
    sign_in
    account.update!(setup_path: :assisted)

    get onboarding_discovery_path

    assert_response :success
    assert_select "[data-testid='discovery-form']"
  end

  test "discovery redirects accounts not on the assisted path" do
    sign_in
    account.update!(setup_path: :self_serve)

    get onboarding_discovery_path

    assert_redirected_to onboarding_path
  end

  test "submit_discovery stores the profile and marks it completed" do
    sign_in
    account.update!(setup_path: :assisted)

    post onboarding_discovery_path,
      params: { setup_profile: { attribution_goal: "b2b_leads", monthly_ad_spend: "25k_100k" } }

    account.reload

    assert_equal "b2b_leads", account.setup_profile["attribution_goal"]
    assert_predicate account, :setup_profile_completed?
  end

  test "submit_discovery redirects to the guided setup page" do
    sign_in
    account.update!(setup_path: :assisted)

    post onboarding_discovery_path, params: { setup_profile: { attribution_goal: "b2b_leads" } }

    assert_redirected_to onboarding_guided_setup_path
  end

  # --- Guided Setup (details + plan picker) ---

  test "guided_setup requires authentication" do
    get onboarding_guided_setup_path

    assert_redirected_to login_path
  end

  test "guided_setup redirects accounts not on the assisted path" do
    sign_in
    account.update!(setup_path: :self_serve)

    get onboarding_guided_setup_path

    assert_redirected_to onboarding_path
  end

  test "guided_setup redirects to discovery if discovery is not completed" do
    sign_in
    account.update!(setup_path: :assisted, setup_profile_completed_at: nil)

    get onboarding_guided_setup_path

    assert_redirected_to onboarding_discovery_path
  end

  test "guided_setup renders the plan picker with the recommended tier pre-selected" do
    sign_in
    account.update!(
      setup_path: :assisted,
      setup_profile: { "monthly_ad_spend" => "over_100k" },
      setup_profile_completed_at: Time.current
    )

    get onboarding_guided_setup_path

    assert_response :success
    assert_select "[data-testid='guided-setup']"
    assert_select "input[type=radio][name='plan_slug'][value='pro'][checked]"
  end

  # --- Accept (Guided Setup -> Stripe Checkout) ---

  test "accept_guided_setup requires authentication" do
    post onboarding_accept_guided_setup_path, params: { plan_slug: "growth" }

    assert_redirected_to login_path
  end

  test "accept_guided_setup requires the assisted path" do
    sign_in
    account.update!(setup_path: :self_serve)

    post onboarding_accept_guided_setup_path, params: { plan_slug: "growth" }

    assert_redirected_to onboarding_path
  end

  test "accept_guided_setup requires a plan to be chosen" do
    sign_in
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)

    post onboarding_accept_guided_setup_path

    assert_redirected_to onboarding_guided_setup_path
    assert_predicate flash[:alert], :present?
  end

  test "accept_guided_setup creates a pending GuidedSetup with the inferred integration target" do
    sign_in
    account.update!(
      setup_path: :assisted,
      setup_profile: { "ad_platforms" => [ "meta" ] },
      setup_profile_completed_at: Time.current,
      stripe_customer_id: "cus_assisted_test"
    )

    assert_difference -> { GuidedSetup.count }, 1 do
      post onboarding_accept_guided_setup_path, params: { plan_slug: "growth" }
    end

    engagement = account.reload.guided_setup

    assert_predicate engagement, :pending?
    assert_equal "meta", engagement.integration_target
    assert_response :redirect
  end

  test "accept_guided_setup is idempotent for the existing pending engagement" do
    sign_in
    account.update!(
      setup_path: :assisted,
      setup_profile_completed_at: Time.current,
      stripe_customer_id: "cus_assisted_test"
    )
    GuidedSetup.create!(account: account)

    assert_no_difference -> { GuidedSetup.count } do
      post onboarding_accept_guided_setup_path, params: { plan_slug: "growth" }
    end
  end

  test "accept_guided_setup re-renders with an alert when the plan is the free plan" do
    sign_in
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)

    post onboarding_accept_guided_setup_path, params: { plan_slug: "free" }

    assert_redirected_to onboarding_guided_setup_path
    assert_includes flash[:alert].to_s, "free plan"
  end

  # --- Confirmation ---

  test "confirmation requires authentication" do
    get onboarding_confirmation_path

    assert_redirected_to login_path
  end

  test "confirmation requires the assisted path" do
    sign_in
    account.update!(setup_path: :self_serve)

    get onboarding_confirmation_path

    assert_redirected_to onboarding_path
  end

  test "confirmation renders the in-progress state when the engagement is live" do
    sign_in
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
    GuidedSetup.create!(account: account, status: :in_progress, accepted_at: Time.current)

    get onboarding_confirmation_path

    assert_response :success
    assert_select "[data-testid='confirmation-form']"
  end

  test "confirmation renders the processing state when the engagement is still pending" do
    sign_in
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
    GuidedSetup.create!(account: account, status: :pending)

    get onboarding_confirmation_path

    assert_response :success
    assert_select "[data-testid='confirmation-processing']"
  end

  test "submit_confirmation stores the structured scheduling preferences" do
    sign_in
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
    engagement = GuidedSetup.create!(account: account, status: :in_progress, accepted_at: Time.current)

    post onboarding_confirmation_path,
      params: { scheduling_preferences: { timezone: "Sydney", days: [ "tue", "wed" ], time_blocks: [ "morning", "afternoon" ] } }

    prefs = engagement.reload.scheduling_preferences

    assert_equal "Sydney", prefs["timezone"]
    assert_equal [ "tue", "wed" ], prefs["days"]
    assert_equal [ "morning", "afternoon" ], prefs["time_blocks"]
    assert_redirected_to dashboard_path
  end

  test "submit_confirmation re-renders with an error when timezone is blank" do
    sign_in
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
    GuidedSetup.create!(account: account, status: :in_progress, accepted_at: Time.current)

    post onboarding_confirmation_path, params: { scheduling_preferences: { timezone: "" } }

    assert_response :unprocessable_entity
    assert_select "[data-testid='scheduling-error']", /time zone/i
  end

  test "submit_confirmation drops unknown day-of-week and time-block values" do
    sign_in
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
    engagement = GuidedSetup.create!(account: account, status: :in_progress, accepted_at: Time.current)

    post onboarding_confirmation_path,
      params: { scheduling_preferences: { timezone: "Sydney", days: [ "tue", "funday" ], time_blocks: [ "morning", "midnight" ] } }

    prefs = engagement.reload.scheduling_preferences

    assert_equal [ "tue" ], prefs["days"]
    assert_equal [ "morning" ], prefs["time_blocks"]
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

    assert_predicate @test_account.api_keys.test, :exists?
  end

  test "setup keeps plaintext key in session for install step" do
    sign_in_as_new_user

    # First view - plaintext shown (dark bg, green text)
    get onboarding_setup_path

    assert_not_nil session[:plaintext_api_key], "Session should keep key for install step"
    assert_select "code.text-green-400", /sk_test_/

    # Key remains available for install page (needed for custom-install SDKs)
    get onboarding_setup_path

    assert_select "code.text-green-400", /sk_test_/
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
    assert_predicate old_key.reload, :revoked?
    assert_predicate session[:plaintext_api_key], :present?
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
    assert_includes flash[:notice], "waitlist"

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

  test "install shows plaintext API key for a custom-install SDK when available" do
    sign_in_as_new_user
    # Visit setup first to create API key and store in session
    get onboarding_setup_path
    @test_account.update!(selected_sdk: "sgtm")

    get onboarding_install_path

    assert_response :success
    assert_select "code.text-green-400", /sk_test_/
  end

  test "install shows regenerate option for a custom-install SDK when key not in session" do
    sign_in
    account.update!(selected_sdk: "sgtm")
    # Don't visit setup, so no plaintext key in session

    get onboarding_install_path

    assert_response :success
    assert_select "button", text: "Regenerate API Key"
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

    refute json["received"]
  end

  test "event_status returns received true when events exist" do
    sign_in

    get onboarding_event_status_path

    assert_response :success
    json = JSON.parse(response.body)

    assert json["received"]
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
