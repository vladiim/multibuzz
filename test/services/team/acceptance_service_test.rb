require "test_helper"

class Team::AcceptanceServiceTest < ActiveSupport::TestCase
  INVITATION_EXPIRY_DAYS = 7

  setup do
    # Ensure pending membership has a token set before tests run
    pending_membership
  end

  # ==========================================
  # Token validation
  # ==========================================

  test "finds membership by valid token" do
    result = accept(token: invitation_token, lookup_only: true)

    assert result[:success]
    assert_equal pending_membership, result[:membership]
  end

  test "rejects invalid token" do
    result = accept(token: "invalid_token")

    assert_not result[:success]
    assert_equal :not_found, result[:error_code]
  end

  test "rejects expired token" do
    pending_membership.update!(invited_at: (INVITATION_EXPIRY_DAYS + 1).days.ago)

    result = accept(token: invitation_token)

    assert_not result[:success]
    assert_equal :expired, result[:error_code]
  end

  test "rejects already accepted invitation" do
    pending_membership.update!(status: :accepted, accepted_at: Time.current)

    result = accept(token: invitation_token)

    assert_not result[:success]
    assert_equal :already_accepted, result[:error_code]
  end

  # ==========================================
  # Acceptance for logged-in user
  # ==========================================

  test "accepts invitation for matching logged-in user" do
    result = accept(token: invitation_token, current_user: invited_user)

    assert result[:success]
    pending_membership.reload
    assert pending_membership.accepted?
  end

  test "sets accepted_at timestamp" do
    freeze_time do
      accept(token: invitation_token, current_user: invited_user)

      pending_membership.reload
      assert_equal Time.current, pending_membership.accepted_at
    end
  end

  test "clears invitation token after acceptance" do
    accept(token: invitation_token, current_user: invited_user)

    pending_membership.reload
    assert_nil pending_membership.invitation_token_digest
  end

  test "rejects if logged-in user doesn't match invitation" do
    result = accept(token: invitation_token, current_user: owner)

    assert_not result[:success]
    assert_equal :wrong_user, result[:error_code]
    pending_membership.reload
    assert pending_membership.pending?
  end

  # ==========================================
  # Acceptance with password (new user)
  # ==========================================

  test "accepts and sets password for new user" do
    result = accept(token: invitation_token, password: "newpassword123", password_confirmation: "newpassword123")

    assert result[:success]
    pending_membership.reload
    assert pending_membership.accepted?
    assert invited_user.reload.authenticate("newpassword123")
  end

  test "rejects mismatched passwords" do
    result = accept(token: invitation_token, password: "newpassword123", password_confirmation: "different123")

    assert_not result[:success]
    assert_equal :validation_error, result[:error_code]
    assert result[:errors].any? { |e| e.match?(/password.*match|confirmation/i) }
  end

  test "rejects short password" do
    result = accept(token: invitation_token, password: "short", password_confirmation: "short")

    assert_not result[:success]
    assert_equal :validation_error, result[:error_code]
  end

  test "rejects blank password" do
    result = accept(token: invitation_token, password: "", password_confirmation: "")

    assert_not result[:success]
    assert_equal :validation_error, result[:error_code]
  end

  # ==========================================
  # Lookup only (for show action)
  # ==========================================

  test "lookup_only returns membership without accepting" do
    result = accept(token: invitation_token, lookup_only: true)

    assert result[:success]
    assert_equal pending_membership, result[:membership]
    pending_membership.reload
    assert pending_membership.pending?
  end

  test "lookup_only still validates expiry" do
    pending_membership.update!(invited_at: (INVITATION_EXPIRY_DAYS + 1).days.ago)

    result = accept(token: invitation_token, lookup_only: true)

    assert_not result[:success]
    assert_equal :expired, result[:error_code]
  end

  private

  def accept(token:, current_user: nil, password: nil, password_confirmation: nil, lookup_only: false)
    Team::AcceptanceService.new(
      token: token,
      current_user: current_user,
      password: password,
      password_confirmation: password_confirmation,
      lookup_only: lookup_only
    ).call
  end

  def owner
    @owner ||= users(:one)
  end

  def invited_user
    @invited_user ||= pending_membership.user
  end

  def pending_membership
    @pending_membership ||= account_memberships(:pending_invite).tap do |m|
      m.update!(invitation_token_digest: Digest::SHA256.hexdigest(invitation_token)) unless m.invitation_token_digest.present?
    end
  end

  def invitation_token
    @invitation_token ||= "test_acceptance_token_12345"
  end
end
