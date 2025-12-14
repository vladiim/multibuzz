require "test_helper"

class Accounts::Team::InvitationsControllerTest < ActionDispatch::IntegrationTest
  # ==========================================
  # Create action - Send invitation
  # ==========================================

  test "create sends invitation to new email" do
    sign_in_as owner

    assert_difference "AccountMembership.count", 1 do
      post account_team_invitations_path, params: { email: "newuser@example.com", role: "member" }
    end

    assert_redirected_to account_team_path
    assert_equal "Invitation sent to newuser@example.com", flash[:notice]
  end

  test "create sends invitation email" do
    sign_in_as owner

    assert_emails 1 do
      post account_team_invitations_path, params: { email: "newuser@example.com", role: "member" }
    end
  end

  test "create sets pending status for invitation" do
    sign_in_as owner

    post account_team_invitations_path, params: { email: "newuser@example.com", role: "member" }

    membership = AccountMembership.last
    assert membership.pending?
    assert_equal "member", membership.role
    assert membership.invitation_token_digest.present?
    assert membership.invited_at.present?
  end

  test "create allows admin role invitation" do
    sign_in_as owner

    post account_team_invitations_path, params: { email: "newadmin@example.com", role: "admin" }

    membership = AccountMembership.last
    assert_equal "admin", membership.role
  end

  test "create rejects owner role invitation" do
    sign_in_as owner

    post account_team_invitations_path, params: { email: "newowner@example.com", role: "owner" }

    assert_redirected_to account_team_path
    assert_match /cannot invite.*owner/i, flash[:alert]
  end

  test "create handles existing user invitation" do
    sign_in_as owner

    # user_two exists but is not a member of account_one (other than pending invite)
    # Let's use a fresh email from users fixture
    existing_user = users(:admin)  # admin user exists but not in account_one

    post account_team_invitations_path, params: { email: existing_user.email, role: "member" }

    assert_redirected_to account_team_path
    membership = AccountMembership.find_by(user: existing_user, account: account)
    assert membership.present?
    assert membership.pending?
  end

  test "create rejects duplicate invitation" do
    sign_in_as owner

    # user_two already has pending invite in account_one
    post account_team_invitations_path, params: { email: user_two.email, role: "member" }

    assert_redirected_to account_team_path
    assert_match /already.*pending|already.*member/i, flash[:alert]
  end

  test "create rejects invitation to existing member" do
    sign_in_as owner

    # admin_user is already an accepted member of account_one
    post account_team_invitations_path, params: { email: admin_user.email, role: "member" }

    assert_redirected_to account_team_path
    assert_match /already.*member/i, flash[:alert]
  end

  test "create requires admin role" do
    sign_in_as member_user

    assert_no_difference "AccountMembership.count" do
      post account_team_invitations_path, params: { email: "newuser@example.com", role: "member" }
    end

    assert_response :forbidden
  end

  test "create allowed for admin" do
    sign_in_as admin_user

    assert_difference "AccountMembership.count", 1 do
      post account_team_invitations_path, params: { email: "newuser@example.com", role: "member" }
    end
  end

  test "create requires authentication" do
    post account_team_invitations_path, params: { email: "newuser@example.com", role: "member" }

    assert_redirected_to login_path
  end

  test "create validates email format" do
    sign_in_as owner

    post account_team_invitations_path, params: { email: "invalid-email", role: "member" }

    assert_redirected_to account_team_path
    assert_match /invalid.*email/i, flash[:alert]
  end

  test "create records invited_by" do
    sign_in_as owner

    post account_team_invitations_path, params: { email: "newuser@example.com", role: "member" }

    membership = AccountMembership.last
    assert_equal owner.id, membership.invited_by_id
  end

  # ==========================================
  # Destroy action - Cancel invitation
  # ==========================================

  test "destroy cancels pending invitation" do
    sign_in_as owner

    assert_difference "AccountMembership.count", -1 do
      delete account_team_invitation_path(pending_membership.prefix_id)
    end

    assert_redirected_to account_team_path
    assert_equal "Invitation cancelled", flash[:notice]
  end

  test "destroy only works on pending invitations" do
    sign_in_as owner

    # Try to destroy accepted membership via invitation path
    delete account_team_invitation_path(admin_membership.prefix_id)

    assert_redirected_to account_team_path
    assert_match /cannot cancel.*accepted/i, flash[:alert]
    assert AccountMembership.exists?(admin_membership.id)
  end

  test "destroy requires admin role" do
    sign_in_as member_user

    delete account_team_invitation_path(pending_membership.prefix_id)

    assert_response :forbidden
    assert AccountMembership.exists?(pending_membership.id)
  end

  test "destroy requires authentication" do
    delete account_team_invitation_path(pending_membership.prefix_id)

    assert_redirected_to login_path
  end

  # ==========================================
  # Resend invitation
  # ==========================================

  test "create with resend param resends invitation email" do
    sign_in_as owner

    assert_emails 1 do
      post account_team_invitations_path, params: { resend: pending_membership.prefix_id }
    end

    assert_redirected_to account_team_path
    assert_match /invitation.*resent/i, flash[:notice]
  end

  test "resend updates invitation token" do
    sign_in_as owner
    old_token = pending_membership.invitation_token_digest

    post account_team_invitations_path, params: { resend: pending_membership.prefix_id }

    pending_membership.reload
    assert_not_equal old_token, pending_membership.invitation_token_digest
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def owner
    @owner ||= users(:one)
  end

  def user_two
    @user_two ||= users(:two)
  end

  def admin_user
    @admin_user ||= users(:three)
  end

  def member_user
    @member_user ||= users(:four)
  end

  def account
    @account ||= accounts(:one)
  end

  def pending_membership
    @pending_membership ||= account_memberships(:pending_invite)
  end

  def admin_membership
    @admin_membership ||= account_memberships(:admin_in_one)
  end
end
