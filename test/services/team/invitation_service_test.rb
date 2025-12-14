require "test_helper"

class Team::InvitationServiceTest < ActiveSupport::TestCase
  # ==========================================
  # New user invitation
  # ==========================================

  test "creates membership for new email" do
    result = invite("newuser@example.com")

    assert result[:success]
    assert result[:membership].pending?
    assert_equal "newuser@example.com", result[:membership].user.email
  end

  test "creates user record for new email" do
    assert_difference "User.count", 1 do
      invite("newuser@example.com")
    end
  end

  test "sets pending status" do
    result = invite("newuser@example.com")

    membership = result[:membership]
    assert membership.pending?
  end

  test "sets default member role" do
    result = invite("newuser@example.com")

    membership = result[:membership]
    assert_equal "member", membership.role
  end

  test "sets specified role" do
    result = invite("newuser@example.com", role: "admin")

    membership = result[:membership]
    assert_equal "admin", membership.role
  end

  test "generates invitation token" do
    result = invite("newuser@example.com")

    membership = result[:membership]
    assert membership.invitation_token_digest.present?
    assert result[:invitation_token].present?
  end

  test "returns unhashed token for email" do
    result = invite("newuser@example.com")

    # Token should be usable to find the membership
    membership = AccountMembership.find_by(
      invitation_token_digest: Digest::SHA256.hexdigest(result[:invitation_token])
    )
    assert_equal result[:membership], membership
  end

  test "sets invited_at timestamp" do
    freeze_time do
      result = invite("newuser@example.com")

      membership = result[:membership]
      assert_equal Time.current, membership.invited_at
    end
  end

  test "sets invited_by_id" do
    result = invite("newuser@example.com")

    membership = result[:membership]
    assert_equal inviter.id, membership.invited_by_id
  end

  # ==========================================
  # Existing user invitation
  # ==========================================

  test "uses existing user record" do
    existing_user = users(:admin)

    assert_no_difference "User.count" do
      result = invite(existing_user.email)

      assert result[:success]
      membership = result[:membership]
      assert_equal existing_user, membership.user
    end
  end

  test "creates membership for existing user" do
    existing_user = users(:admin)

    result = invite(existing_user.email)

    assert result[:success]
    membership = AccountMembership.find_by(user: existing_user, account: account)
    assert membership.present?
    assert membership.pending?
  end

  # ==========================================
  # Validation errors
  # ==========================================

  test "rejects owner role" do
    result = invite("newuser@example.com", role: "owner")

    assert_not result[:success]
    assert_includes result[:errors], "Cannot invite with owner role"
  end

  test "rejects invalid email format" do
    result = invite("not-an-email")

    assert_not result[:success]
    assert result[:errors].any? { |e| e.match?(/invalid.*email/i) }
  end

  test "rejects blank email" do
    result = invite("")

    assert_not result[:success]
    assert result[:errors].any? { |e| e.match?(/email.*required|blank/i) }
  end

  test "rejects duplicate pending invitation" do
    # user_two has pending invite in account_one already
    result = invite(users(:two).email)

    assert_not result[:success]
    assert result[:errors].any? { |e| e.match?(/already.*invited|pending/i) }
  end

  test "rejects invitation to existing member" do
    # admin_user is already an accepted member of account_one
    result = invite(users(:three).email)

    assert_not result[:success]
    assert result[:errors].any? { |e| e.match?(/already.*member/i) }
  end

  test "rejects self-invitation" do
    result = invite(inviter.email)

    assert_not result[:success]
    assert result[:errors].any? { |e| e.match?(/cannot.*invite.*yourself|self/i) }
  end

  # ==========================================
  # Resend invitation
  # ==========================================

  test "resend generates new token" do
    pending = account_memberships(:pending_invite)
    old_digest = pending.invitation_token_digest

    result = resend(pending)

    assert result[:success]
    pending.reload
    assert_not_equal old_digest, pending.invitation_token_digest
  end

  test "resend updates invited_at" do
    pending = account_memberships(:pending_invite)

    freeze_time do
      result = resend(pending)

      assert result[:success]
      pending.reload
      assert_equal Time.current, pending.invited_at
    end
  end

  test "resend only works for pending invitations" do
    accepted = account_memberships(:admin_in_one)

    result = resend(accepted)

    assert_not result[:success]
    assert result[:errors].any? { |e| e.match?(/only.*pending|not.*pending/i) }
  end

  private

  def invite(email, role: "member")
    Team::InvitationService.new(
      account: account,
      inviter: inviter,
      email: email,
      role: role
    ).call
  end

  def resend(membership)
    Team::InvitationService.new(
      account: account,
      inviter: inviter,
      resend_membership: membership
    ).call
  end

  def account
    @account ||= accounts(:one)
  end

  def inviter
    @inviter ||= users(:one)
  end
end
