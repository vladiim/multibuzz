require "test_helper"

class Dashboard::BillingBannerTest < ActionDispatch::IntegrationTest
  setup do
    # Complete onboarding so default view mode is production (no test mode banner)
    accounts(:one).update!(onboarding_progress: (1 << Account::Onboarding::ONBOARDING_STEPS.size) - 1)
    sign_in_as users(:one)
  end

  test "shows past_due banner when payment failed" do
    account.update!(
      billing_status: :past_due,
      payment_failed_at: 5.days.ago,
      grace_period_ends_at: 2.days.ago
    )

    get dashboard_path

    assert_response :success
    assert_select ".bg-red-50", text: /Payment failed/
    assert_select "a", text: "Update Payment"
  end

  test "shows free_until_expiring banner when expiring soon" do
    account.update!(
      billing_status: :free_until,
      free_until: 5.days.from_now
    )

    get dashboard_path

    assert_response :success
    assert_select ".bg-blue-50", text: /Free access ends in 5 days/
    assert_select "a", text: "View Plans"
  end

  test "shows usage_limit banner when at 100%" do
    account.update!(billing_status: :free_forever, plan: plans(:free))
    Rails.cache.write(account.usage_cache_key, Billing::FREE_EVENT_LIMIT)

    get dashboard_path

    assert_response :success
    assert_select ".bg-amber-50", text: /Event limit reached/
    assert_select "a", text: "Upgrade Now"
  end

  test "shows usage_warning banner when at 80%" do
    account.update!(billing_status: :free_forever, plan: plans(:free))
    Rails.cache.write(account.usage_cache_key, (Billing::FREE_EVENT_LIMIT * 0.8).to_i)

    get dashboard_path

    assert_response :success
    assert_select ".bg-amber-50", text: /Approaching event limit/
    assert_select "a", text: "View Plans"
  end

  test "shows no banner for active paid account" do
    account.update!(billing_status: :active, plan: plans(:starter))
    Rails.cache.write(account.usage_cache_key, 1000)

    get dashboard_path

    assert_response :success
    assert_select ".bg-red-50", count: 0
    assert_select ".bg-blue-50", count: 0
    assert_select ".bg-amber-50", count: 0
  end

  test "past_due banner takes priority over usage warnings" do
    account.update!(
      billing_status: :past_due,
      payment_failed_at: 5.days.ago,
      grace_period_ends_at: 2.days.ago,
      plan: plans(:free)
    )
    Rails.cache.write(account.usage_cache_key, Billing::FREE_EVENT_LIMIT)

    get dashboard_path

    assert_response :success
    assert_select ".bg-red-50", text: /Payment failed/
    assert_select ".bg-amber-50", count: 0
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def account
    @account ||= accounts(:one)
  end
end
