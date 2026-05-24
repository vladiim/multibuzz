# frozen_string_literal: true

require "test_helper"

class AccountCreditTest < ActiveSupport::TestCase
  test "is valid with an account, plan, amount, source and granted_at" do
    assert_predicate credit, :valid?
  end

  test "defaults to active" do
    assert_predicate credit, :active?
  end

  test "requires a positive amount_cents" do
    assert_not new_credit(amount_cents: 0).valid?
  end

  test "requires a source" do
    assert_not new_credit(source: nil).valid?
  end

  test "requires granted_at" do
    assert_not new_credit(granted_at: nil).valid?
  end

  test "belongs to a plan via applied_plan" do
    assert_equal plan, credit.applied_plan
  end

  test "active scope excludes voided credits" do
    voided = AccountCredit.create!(
      account: account, applied_plan: plan, source: "guided_setup",
      granted_at: Time.current, amount_cents: 150_000, status: :voided
    )

    assert_includes AccountCredit.active, credit
    assert_not_includes AccountCredit.active, voided
  end

  test "is scoped to its account" do
    other = AccountCredit.create!(
      account: other_account, applied_plan: plan, source: "guided_setup",
      granted_at: Time.current, amount_cents: 150_000
    )

    assert_includes account.account_credits, credit
    assert_not_includes account.account_credits, other
  end

  test "exposes a prefixed id" do
    assert_match(/\Acred_/, credit.prefix_id)
  end

  private

  def account = @account ||= accounts(:one)
  def other_account = @other_account ||= accounts(:two)
  def plan = @plan ||= plans(:growth)

  def credit
    @credit ||= AccountCredit.create!(
      account: account, applied_plan: plan, source: "guided_setup",
      granted_at: Time.current, amount_cents: 150_000
    )
  end

  def new_credit(**overrides)
    AccountCredit.new({
      account: account, applied_plan: plan, source: "guided_setup",
      granted_at: Time.current, amount_cents: 150_000
    }.merge(overrides))
  end
end
