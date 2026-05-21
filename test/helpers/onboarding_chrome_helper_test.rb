# frozen_string_literal: true

require "test_helper"

class OnboardingChromeHelperTest < ActionView::TestCase
  # --- onboarding_branch_label ---

  test "branch label is nil when current_account is nil" do
    @current_account = nil

    assert_nil onboarding_branch_label
  end

  test "branch label is nil when setup_path is nil" do
    account.update!(setup_path: nil)

    assert_nil onboarding_branch_label
  end

  test "branch label maps self_serve to Self-serve setup" do
    account.update!(setup_path: :self_serve)

    assert_equal "Self-serve setup", onboarding_branch_label
  end

  test "branch label maps teammate to Teammate setup" do
    account.update!(setup_path: :teammate)

    assert_equal "Teammate setup", onboarding_branch_label
  end

  test "branch label maps assisted to Guided Setup" do
    account.update!(setup_path: :assisted)

    assert_equal "Guided Setup", onboarding_branch_label
  end

  # --- onboarding_pips: visibility ---

  test "pips list is empty when current_account is nil" do
    @current_account = nil
    @onboarding_current_pip = :discovery

    assert_empty onboarding_pips
  end

  test "pips list is empty when no setup_path is chosen" do
    account.update!(setup_path: nil)
    @onboarding_current_pip = :discovery

    assert_empty onboarding_pips
  end

  test "pips list is empty when no current_pip is set" do
    account.update!(setup_path: :assisted)
    @onboarding_current_pip = nil

    assert_empty onboarding_pips
  end

  # --- onboarding_pips: states ---

  test "assisted pip sequence has the expected keys" do
    account.update!(setup_path: :assisted)
    @onboarding_current_pip = :discovery

    assert_equal %i[pick_path discovery book_kickoff pay done], onboarding_pips.map(&:key)
  end

  # --- first pip label is the branch choice phrase ---

  test "self-serve first pip label is the I'll-do-it phrase" do
    account.update!(setup_path: :self_serve)
    @onboarding_current_pip = :api_key

    assert_equal "I'll do it", pip(:pick_path).label
  end

  test "teammate first pip label is the my-teammate-will phrase" do
    account.update!(setup_path: :teammate)
    @onboarding_current_pip = :invite_sent

    assert_equal "My teammate will", pip(:pick_path).label
  end

  test "assisted first pip label is the mbuzz-will-do-it phrase" do
    account.update!(setup_path: :assisted)
    @onboarding_current_pip = :discovery

    assert_equal "mbuzz will do it", pip(:pick_path).label
  end

  test "pip before the current one is marked done" do
    account.update!(setup_path: :assisted)
    @onboarding_current_pip = :discovery

    assert_equal :done, pip(:pick_path).state
  end

  test "pip matching the current one is marked current" do
    account.update!(setup_path: :assisted)
    @onboarding_current_pip = :discovery

    assert_equal :current, pip(:discovery).state
  end

  test "pip after the current one is marked upcoming" do
    account.update!(setup_path: :assisted)
    @onboarding_current_pip = :discovery

    assert_equal :upcoming, pip(:book_kickoff).state
  end

  test "self-serve sequence renders without any locked pips" do
    account.update!(setup_path: :self_serve)
    @onboarding_current_pip = :install

    states = onboarding_pips.map(&:state)

    assert_not_includes states, :locked
  end

  test "teammate sequence renders without any locked pips" do
    account.update!(setup_path: :teammate)
    @onboarding_current_pip = :invite_sent

    states = onboarding_pips.map(&:state)

    assert_not_includes states, :locked
  end

  # --- onboarding_pips: locked pay on the assisted path ---

  test "assisted pay pip is locked when no GuidedSetup exists" do
    account.update!(setup_path: :assisted)
    @onboarding_current_pip = :discovery

    assert_equal :locked, pip(:pay).state
  end

  test "assisted pay pip is locked when the engagement is pending with no active token" do
    account.update!(setup_path: :assisted)
    GuidedSetup.create!(account: account)
    @onboarding_current_pip = :discovery

    assert_equal :locked, pip(:pay).state
  end

  test "assisted pay pip is upcoming when the payment token is active" do
    account.update!(setup_path: :assisted)
    GuidedSetup.create!(account: account).mint_payment_token!
    @onboarding_current_pip = :discovery

    assert_equal :upcoming, pip(:pay).state
  end

  test "assisted pay pip is upcoming once the engagement is in_progress" do
    account.update!(setup_path: :assisted)
    GuidedSetup.create!(account: account, status: :in_progress, accepted_at: Time.current)
    @onboarding_current_pip = :discovery

    assert_equal :upcoming, pip(:pay).state
  end

  # --- onboarding_pip_link (clickable done pips for back-navigation) ---

  test "pip link is nil for the current pip" do
    account.update!(setup_path: :assisted)
    @onboarding_current_pip = :discovery

    assert_nil onboarding_pip_link(pip(:discovery))
  end

  test "pip link is nil for upcoming pips" do
    account.update!(setup_path: :assisted)
    @onboarding_current_pip = :discovery

    assert_nil onboarding_pip_link(pip(:book_kickoff))
  end

  test "pip link is nil for locked pips" do
    account.update!(setup_path: :assisted)
    @onboarding_current_pip = :discovery

    assert_nil onboarding_pip_link(pip(:pay))
  end

  test "done pick_path pip links back to clear the setup_path when the branch is uncommitted" do
    account.update!(setup_path: :assisted, setup_profile_completed_at: nil)
    @onboarding_current_pip = :discovery

    link = onboarding_pip_link(pip(:pick_path))

    assert_equal onboarding_change_setup_path_path, link[:path]
    assert_equal :delete, link[:method]
  end

  test "pick_path pip is not clickable once self-serve has received events" do
    account.update!(setup_path: :self_serve)
    @onboarding_current_pip = :install
    # fixtures already give accounts(:one) events

    assert_nil onboarding_pip_link(pip(:pick_path))
  end

  test "pick_path pip is not clickable once a teammate invite has been sent" do
    account.update!(setup_path: :teammate)
    @onboarding_current_pip = :invite_sent
    # fixtures already give accounts(:one) a pending non-owner membership

    assert_nil onboarding_pip_link(pip(:pick_path))
  end

  test "pick_path pip is not clickable once assisted discovery is complete" do
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
    @onboarding_current_pip = :book_kickoff

    assert_nil onboarding_pip_link(pip(:pick_path))
  end

  # --- onboarding_current_pip_label ---

  test "current pip label returns the current pip's human label" do
    @onboarding_current_pip = :discovery

    assert_equal "About", onboarding_current_pip_label
  end

  test "current pip label is nil when no current pip is set" do
    @onboarding_current_pip = nil

    assert_nil onboarding_current_pip_label
  end

  # --- onboarding_resume_status (the main-app nav pill) ---

  test "resume status is nil when current_account is nil" do
    @current_account = nil

    assert_nil onboarding_resume_status
  end

  test "resume status is nil when no setup_path has been chosen" do
    account.update!(setup_path: nil)

    assert_nil onboarding_resume_status
  end

  test "resume status is nil when onboarding was skipped" do
    account.update!(setup_path: :self_serve, onboarding_skipped_at: Time.current)

    assert_nil onboarding_resume_status
  end

  test "self-serve resume status points at the attribution screen until it has been viewed" do
    account.update!(setup_path: :self_serve)

    assert_equal onboarding_setup_path, onboarding_resume_status.path
    assert_equal "Finish setup", onboarding_resume_status.label
  end

  test "self-serve resume status is nil once attribution has been viewed" do
    account.update!(setup_path: :self_serve)
    account.complete_onboarding_step!(:attribution_viewed)

    assert_nil onboarding_resume_status
  end

  test "teammate resume status invites the user to send an invite when no memberships exist" do
    account.update!(setup_path: :teammate)
    account.account_memberships.where.not(role: :owner).destroy_all

    status = onboarding_resume_status

    assert_equal onboarding_invite_teammate_path, status.path
    assert status.actionable
    assert_match(/invite your teammate/i, status.label)
  end

  test "teammate resume status reports 'awaiting your teammate' while invites are pending" do
    account.update!(setup_path: :teammate)
    # The fixtures supply a pending invite for accounts(:one).

    status = onboarding_resume_status

    assert_not status.actionable
    assert_match(/awaiting your teammate/i, status.label)
  end

  test "teammate resume status reports 'awaiting first event' once teammate accepted but no events yet" do
    account.update!(setup_path: :teammate)
    account.account_memberships.where(status: :pending).update_all(status: :accepted, accepted_at: Time.current)
    account.events.destroy_all

    status = onboarding_resume_status

    assert_not status.actionable
    assert_match(/first event/i, status.label)
  end

  test "teammate resume status is nil once the teammate has accepted and events have landed" do
    account.update!(setup_path: :teammate)
    account.account_memberships.where(status: :pending).update_all(status: :accepted, accepted_at: Time.current)
    # account :one has events in fixtures.

    assert_nil onboarding_resume_status
  end

  test "assisted resume status routes to install_service before discovery is done" do
    account.update!(setup_path: :assisted, setup_profile_completed_at: nil)

    assert_equal onboarding_install_service_path, onboarding_resume_status.path
  end

  test "assisted resume status routes to book-kickoff once discovery is done" do
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)

    assert_equal onboarding_guided_setup_path, onboarding_resume_status.path
  end

  test "assisted resume status is non-actionable but still links back to onboarding once the kickoff is booked" do
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
    GuidedSetup.create!(account: account, kickoff_booked_at: Time.current)

    status = onboarding_resume_status

    assert_not status.actionable
    assert_equal onboarding_guided_setup_path, status.path
    assert_match(/booked/i, status.label)
  end

  test "assisted resume status routes to payment_setup when a payment token is active" do
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
    GuidedSetup.create!(account: account, kickoff_booked_at: Time.current).mint_payment_token!

    assert_equal onboarding_payment_setup_path, onboarding_resume_status.path
  end

  test "assisted resume status is non-actionable but links to payment_complete once paid and in progress" do
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
    GuidedSetup.create!(account: account, kickoff_booked_at: Time.current, status: :in_progress, accepted_at: Time.current)

    status = onboarding_resume_status

    assert_not status.actionable
    assert_equal onboarding_payment_complete_path, status.path
  end

  test "assisted resume status is nil once the engagement is delivered" do
    account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
    GuidedSetup.create!(account: account, status: :delivered, completed_at: Time.current)

    assert_nil onboarding_resume_status
  end

  # --- onboarding_pip_dot_classes ---

  test "pip dot classes for done and current use the indigo fill" do
    assert_includes onboarding_pip_dot_classes(:done), "bg-indigo-600"
    assert_includes onboarding_pip_dot_classes(:current), "ring"
  end

  test "pip dot classes for upcoming and locked use a white fill" do
    assert_includes onboarding_pip_dot_classes(:upcoming), "bg-white"
    assert_includes onboarding_pip_dot_classes(:locked), "border-dashed"
  end

  # --- onboarding_pip_connector_classes ---

  test "connector after a done pip is indigo" do
    assert_includes onboarding_pip_connector_classes(:done), "indigo"
  end

  test "connector after a non-done pip is gray" do
    assert_includes onboarding_pip_connector_classes(:current), "gray"
    assert_includes onboarding_pip_connector_classes(:upcoming), "gray"
    assert_includes onboarding_pip_connector_classes(:locked), "gray"
  end

  private

  def current_account
    @current_account
  end

  def account
    @current_account ||= accounts(:one)
  end

  def pip(key)
    onboarding_pips.find { |p| p.key == key }
  end
end
