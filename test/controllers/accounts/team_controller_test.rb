require "test_helper"

class Accounts::TeamControllerTest < ActionDispatch::IntegrationTest
  # ==========================================
  # Show action - Team list page
  # ==========================================

  test "show renders team members page" do
    sign_in_as owner

    get account_team_path

    assert_response :success
    assert_select "h1", text: /Team Members/i
  end

  test "show displays all team members for owner" do
    sign_in_as owner

    get account_team_path

    assert_response :success
    # Should show owner, admin, member, and pending invite
    assert_select "table tbody tr", minimum: 3
  end

  test "show displays member roles" do
    sign_in_as owner

    get account_team_path

    assert_response :success
    # Owner role shown as badge (non-editable)
    assert_select "span", text: /Owner/i
    # Other roles shown in select dropdowns for admins
    assert_select "select option", text: /Admin/i
    assert_select "select option", text: /Member/i
  end

  test "show displays pending invitations" do
    sign_in_as owner

    get account_team_path

    assert_response :success
    assert_select "span", text: /Pending/i
  end

  test "show accessible by admin" do
    sign_in_as admin_user

    get account_team_path

    assert_response :success
    assert_select "h1", text: /Team Members/i
  end

  test "show accessible by member" do
    sign_in_as member_user

    get account_team_path

    assert_response :success
    assert_select "h1", text: /Team Members/i
  end

  test "show requires authentication" do
    get account_team_path

    assert_redirected_to login_path
  end

  test "show only displays members from current account" do
    sign_in_as owner

    get account_team_path

    # user_two has pending invite in account_one (shown once in table)
    # user_two also owns account_two but that shouldn't appear
    assert_select "table tbody tr", minimum: 4  # owner, admin, member, pending
    # Ensure we're showing account one's members, not account two's
    assert_select ".text-sm.font-medium", text: owner.email
  end

  # ==========================================
  # Authorization - Admin-only actions
  # ==========================================

  test "owner sees invite form" do
    sign_in_as owner

    get account_team_path

    assert_response :success
    assert_select "form[action=?]", account_team_invitations_path
  end

  test "admin sees invite form" do
    sign_in_as admin_user

    get account_team_path

    assert_response :success
    assert_select "form[action=?]", account_team_invitations_path
  end

  test "member does not see invite form" do
    sign_in_as member_user

    get account_team_path

    assert_response :success
    assert_select "form[action=?]", account_team_invitations_path, count: 0
  end

  test "owner sees role change controls" do
    sign_in_as owner

    get account_team_path

    assert_response :success
    assert_select "select[name*='role']", minimum: 1
  end

  test "admin sees role change controls" do
    sign_in_as admin_user

    get account_team_path

    assert_response :success
    assert_select "select[name*='role']", minimum: 1
  end

  test "member does not see role change controls" do
    sign_in_as member_user

    get account_team_path

    assert_response :success
    assert_select "select[name*='role']", count: 0
  end

  test "owner sees remove buttons for non-owners" do
    sign_in_as owner

    get account_team_path

    assert_response :success
    # Remove buttons for admin and member, but not for owner
    assert_select "button[data-confirm]", minimum: 2
  end

  test "member does not see remove buttons" do
    sign_in_as member_user

    get account_team_path

    assert_response :success
    assert_select "button[data-confirm]", count: 0
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

  def owner_membership
    @owner_membership ||= account_memberships(:owner_one)
  end

  def admin_membership
    @admin_membership ||= account_memberships(:admin_in_one)
  end

  def member_membership
    @member_membership ||= account_memberships(:member_in_one)
  end

  def pending_membership
    @pending_membership ||= account_memberships(:pending_invite)
  end
end
