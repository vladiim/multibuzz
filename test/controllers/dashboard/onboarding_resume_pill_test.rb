# frozen_string_literal: true

require "test_helper"

module Dashboard
  # Integration coverage for the resume pill rendered in the main app
  # nav (app/views/shared/_onboarding_resume_pill.html.erb). Helper-level
  # branching is covered in test/helpers/onboarding_chrome_helper_test.rb;
  # this just confirms the partial actually appears (or doesn't) on
  # /dashboard for each high-level state.
  class OnboardingResumePillTest < ActionDispatch::IntegrationTest
    setup do
      sign_in_as(users(:one))
      account.events.destroy_all
    end

    test "fresh account with no setup_path gets a 'Start setup' pill linking to onboarding" do
      account.update!(setup_path: nil)

      get dashboard_path

      assert_select "a[data-testid='onboarding-resume-pill'][href=?]", onboarding_path, text: /Start setup/
    end

    test "no pill when onboarding was skipped" do
      account.update!(setup_path: :self_serve, onboarding_skipped_at: Time.current)

      get dashboard_path

      assert_select "[data-testid='onboarding-resume-pill']", count: 0
    end

    test "self-serve renders an actionable pill linking to the next incomplete step" do
      account.update!(setup_path: :self_serve)

      get dashboard_path

      assert_select "a[data-testid='onboarding-resume-pill'][href=?]", onboarding_setup_path, text: /Finish setup/
    end

    test "assisted renders an actionable Pay pill the moment kickoff is booked" do
      account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
      GuidedSetup.create!(account: account, kickoff_booked_at: Time.current)

      get dashboard_path

      assert_select "a[data-testid='onboarding-resume-pill'][href=?]", onboarding_payment_setup_path, text: /Pay/
    end

    test "no pill once the assisted engagement is delivered" do
      account.update!(setup_path: :assisted, setup_profile_completed_at: Time.current)
      GuidedSetup.create!(account: account, status: :delivered, completed_at: Time.current)

      get dashboard_path

      assert_select "[data-testid='onboarding-resume-pill']", count: 0
    end

    private

    def account = @account ||= accounts(:one)
  end
end
