# frozen_string_literal: true

require "test_helper"

class GuidedSetupTest < ActiveSupport::TestCase
  test "is valid with an account" do
    assert_predicate guided_setup, :valid?
  end

  test "defaults to pending" do
    assert_predicate guided_setup, :pending?
  end

  test "defaults the integration target to none" do
    assert_predicate guided_setup, :integration_none?
  end

  test "mark_in_progress! sets the status and stamps accepted_at" do
    guided_setup.mark_in_progress!

    assert_predicate guided_setup, :in_progress?
    assert_predicate guided_setup.accepted_at, :present?
  end

  test "record_milestone! stamps the milestone timestamp" do
    guided_setup.record_milestone!(:kickoff_call)

    assert_predicate guided_setup.kickoff_call_at, :present?
  end

  test "recording the value check delivers the engagement" do
    guided_setup.mark_in_progress!
    guided_setup.record_milestone!(:value_check)

    assert_predicate guided_setup, :delivered?
    assert_predicate guided_setup.completed_at, :present?
  end

  test "record_milestone! rejects an unknown milestone" do
    assert_raises(ArgumentError) { guided_setup.record_milestone!(:lunch) }
  end

  test "cancel! marks the engagement cancelled" do
    guided_setup.cancel!

    assert_predicate guided_setup, :cancelled?
  end

  test "stalled scope is in-progress engagements untouched for over 14 days" do
    stale = GuidedSetup.create!(account: accounts(:one))
    stale.update_columns(status: GuidedSetup.statuses[:in_progress], updated_at: 20.days.ago)
    fresh = GuidedSetup.create!(account: accounts(:two), status: :in_progress)

    assert_includes GuidedSetup.stalled, stale
    assert_not_includes GuidedSetup.stalled, fresh
  end

  test "allows only one engagement per account" do
    GuidedSetup.create!(account: account)
    duplicate = GuidedSetup.new(account: account)

    assert_not duplicate.valid?
  end

  test "exposes a prefixed id" do
    assert_match(/\Agst_/, guided_setup.prefix_id)
  end

  test "is reachable from its account" do
    assert_equal guided_setup, account.reload.guided_setup
  end

  private

  def account = @account ||= accounts(:one)

  def guided_setup
    @guided_setup ||= GuidedSetup.create!(account: account)
  end
end
