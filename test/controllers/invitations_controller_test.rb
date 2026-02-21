# frozen_string_literal: true

require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    # Ensure pending membership has a token set before tests run
    pending_membership
  end

  # ==========================================
  # Show action - Accept invitation page
  # ==========================================

  test "show renders acceptance page for valid token" do
    get accept_invitation_path(token: invitation_token)

    assert_response :success
    assert_select "h1", text: /join/i
  end

  test "show displays account name" do
    get accept_invitation_path(token: invitation_token)

    assert_response :success
    assert_select "h1", text: /#{account.name}/
  end

  test "show displays inviter email" do
    get accept_invitation_path(token: invitation_token)

    assert_response :success
    assert_select "p", text: /#{pending_membership.invited_by_email}/
  end

  test "show renders error for invalid token" do
    get accept_invitation_path(token: "invalid_token")

    assert_response :not_found
  end

  test "show renders error for expired token" do
    pending_membership.update!(invited_at: 8.days.ago)

    get accept_invitation_path(token: invitation_token)

    assert_response :gone
    assert_select "p", text: /expired/i
  end

  test "show renders error for already accepted invitation" do
    pending_membership.update!(status: :accepted, accepted_at: Time.current)

    get accept_invitation_path(token: invitation_token)

    assert_response :gone
    assert_select "p", text: /already.*accepted/i
  end

  # ==========================================
  # Create action - Accept invitation (existing user logged in)
  # ==========================================

  test "create accepts invitation for logged in user" do
    sign_in_as invited_user

    post accept_invitation_path(token: invitation_token)

    assert_redirected_to dashboard_path
    pending_membership.reload

    assert_predicate pending_membership, :accepted?
    assert_predicate pending_membership.accepted_at, :present?
  end

  test "create clears invitation token after acceptance" do
    sign_in_as invited_user

    post accept_invitation_path(token: invitation_token)

    pending_membership.reload

    assert_nil pending_membership.invitation_token_digest
  end

  test "create rejects if logged in as different user" do
    sign_in_as owner  # Different user than invited

    post accept_invitation_path(token: invitation_token)

    assert_response :forbidden
    assert_select "p", text: /different.*account|wrong.*user/i
  end

  # ==========================================
  # Create action - Accept invitation (new user registration)
  # ==========================================

  test "create with password sets password and accepts" do
    post accept_invitation_path(token: invitation_token), params: {
      password: "newpassword123",
      password_confirmation: "newpassword123"
    }

    assert_redirected_to dashboard_path
    pending_membership.reload

    assert_predicate pending_membership, :accepted?
    assert invited_user.reload.authenticate("newpassword123")
  end

  test "create with password logs user in" do
    post accept_invitation_path(token: invitation_token), params: {
      password: "newpassword123",
      password_confirmation: "newpassword123"
    }

    assert_redirected_to dashboard_path
    # Follow redirect and verify logged in
    follow_redirect!

    assert_response :success
  end

  test "create rejects mismatched passwords" do
    post accept_invitation_path(token: invitation_token), params: {
      password: "newpassword123",
      password_confirmation: "different123"
    }

    assert_response :unprocessable_entity
    pending_membership.reload

    assert_predicate pending_membership, :pending?
  end

  test "create rejects short password" do
    post accept_invitation_path(token: invitation_token), params: {
      password: "short",
      password_confirmation: "short"
    }

    assert_response :unprocessable_entity
    pending_membership.reload

    assert_predicate pending_membership, :pending?
  end

  test "create rejects invalid token" do
    post accept_invitation_path(token: "invalid_token"), params: {
      password: "newpassword123",
      password_confirmation: "newpassword123"
    }

    assert_response :not_found
  end

  test "create rejects expired token" do
    pending_membership.update!(invited_at: 8.days.ago)

    post accept_invitation_path(token: invitation_token), params: {
      password: "newpassword123",
      password_confirmation: "newpassword123"
    }

    assert_response :gone
  end

  # ==========================================
  # Accept pending action (logged in user from nav)
  # ==========================================

  test "accept_pending accepts invitation for logged in user" do
    sign_in_as invited_user

    post accept_pending_invitation_path(pending_membership.prefix_id)

    assert_redirected_to dashboard_path(account_id: account.prefix_id)
    pending_membership.reload

    assert_predicate pending_membership, :accepted?
  end

  test "accept_pending redirects to login if not logged in" do
    post accept_pending_invitation_path(pending_membership.prefix_id)

    assert_redirected_to login_path
  end

  test "accept_pending fails for wrong user" do
    sign_in_as owner

    post accept_pending_invitation_path(pending_membership.prefix_id)

    assert_redirected_to dashboard_path
    pending_membership.reload

    assert_predicate pending_membership, :pending?
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def owner
    @owner ||= users(:one)
  end

  def invited_user
    @invited_user ||= pending_membership.user
  end

  def account
    @account ||= accounts(:one)
  end

  def pending_membership
    @pending_membership ||= account_memberships(:pending_invite).tap do |m|
      # Ensure token is set for tests
      m.update!(invitation_token_digest: Digest::SHA256.hexdigest(invitation_token)) unless m.invitation_token_digest.present?
    end
  end

  def invitation_token
    @invitation_token ||= "test_invitation_token_12345"
  end
end
