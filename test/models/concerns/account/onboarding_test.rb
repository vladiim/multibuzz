# frozen_string_literal: true

require "test_helper"

class Account::OnboardingTest < ActiveSupport::TestCase
  # Step completion tests
  test "account_created step is completed by default" do
    assert account.onboarding_step_completed?(:account_created)
  end

  test "onboarding_step_completed? returns false for incomplete steps" do
    assert_not account.onboarding_step_completed?(:persona_selected)
    assert_not account.onboarding_step_completed?(:first_event_received)
  end

  test "complete_onboarding_step! marks step as completed" do
    assert_not account.onboarding_step_completed?(:persona_selected)

    account.complete_onboarding_step!(:persona_selected)

    assert account.onboarding_step_completed?(:persona_selected)
  end

  test "complete_onboarding_step! persists to database" do
    account.complete_onboarding_step!(:api_key_viewed)

    account.reload

    assert account.onboarding_step_completed?(:api_key_viewed)
  end

  test "complete_onboarding_step! ignores invalid steps" do
    original_progress = account.onboarding_progress

    account.complete_onboarding_step!(:invalid_step)

    assert_equal original_progress, account.onboarding_progress
  end

  test "completing multiple steps accumulates correctly" do
    account.complete_onboarding_step!(:persona_selected)
    account.complete_onboarding_step!(:api_key_viewed)
    account.complete_onboarding_step!(:sdk_selected)

    assert account.onboarding_step_completed?(:account_created)
    assert account.onboarding_step_completed?(:persona_selected)
    assert account.onboarding_step_completed?(:api_key_viewed)
    assert account.onboarding_step_completed?(:sdk_selected)
    assert_not account.onboarding_step_completed?(:first_event_received)
  end

  # Current step tests
  test "current_onboarding_step returns first incomplete step" do
    assert_equal :persona_selected, account.current_onboarding_step

    account.complete_onboarding_step!(:persona_selected)

    assert_equal :api_key_viewed, account.current_onboarding_step

    account.complete_onboarding_step!(:api_key_viewed)

    assert_equal :sdk_selected, account.current_onboarding_step
  end

  test "current_onboarding_step returns onboarding_complete when all done" do
    complete_all_steps!

    assert_equal :onboarding_complete, account.current_onboarding_step
  end

  # Progress percentage tests
  test "onboarding_percentage returns correct value" do
    # Only account_created (1 of 9)
    assert_equal 11, account.onboarding_percentage

    account.complete_onboarding_step!(:persona_selected)
    # 2 of 9
    assert_equal 22, account.onboarding_percentage
  end

  test "onboarding_percentage returns 100 when complete" do
    complete_all_steps!

    assert_equal 100, account.onboarding_percentage
  end

  # Completion tests
  test "onboarding_complete? returns false when steps remain" do
    assert_not account.onboarding_complete?
  end

  test "onboarding_complete? returns true when all steps done" do
    complete_all_steps!

    assert_predicate account, :onboarding_complete?
  end

  # Activation tests
  test "activated? returns false when first_conversion not completed" do
    account.complete_onboarding_step!(:attribution_viewed)

    assert_not account.activated?
  end

  test "activated? returns false when attribution_viewed not completed" do
    account.complete_onboarding_step!(:first_conversion)

    assert_not account.activated?
  end

  test "activated? returns true when both milestones completed" do
    account.complete_onboarding_step!(:first_conversion)
    account.complete_onboarding_step!(:attribution_viewed)

    assert_predicate account, :activated?
  end

  # Persona tests
  test "onboarding_persona enum works correctly" do
    account.developer!

    assert_predicate account, :developer?

    account.marketer!

    assert_predicate account, :marketer?

    account.both!

    assert_predicate account, :both?
  end

  # Timestamp tests
  test "complete_onboarding_step! sets onboarding_completed_at when all required steps done" do
    assert_nil account.onboarding_completed_at

    complete_all_steps!

    assert_not_nil account.onboarding_completed_at
  end

  test "complete_onboarding_step! sets activated_at when activation milestone reached" do
    assert_nil account.activated_at

    account.complete_onboarding_step!(:first_conversion)

    assert_nil account.activated_at

    account.complete_onboarding_step!(:attribution_viewed)

    assert_not_nil account.activated_at
  end

  # Required steps list
  test "ONBOARDING_STEPS contains all expected steps in order" do
    expected = [
      :account_created,
      :persona_selected,
      :api_key_viewed,
      :sdk_selected,
      :first_event_received,
      :first_conversion,
      :attribution_viewed,
      :identity_linked,
      :onboarding_complete
    ]

    assert_equal expected, Account::Onboarding::ONBOARDING_STEPS
  end

  private

  def account
    @account ||= accounts(:one)
  end

  def complete_all_steps!
    Account::Onboarding::ONBOARDING_STEPS.each do |step|
      account.complete_onboarding_step!(step)
    end
  end
end
