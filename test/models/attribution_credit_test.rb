require "test_helper"

class AttributionCreditTest < ActiveSupport::TestCase
  test "should belong to account" do
    assert_respond_to credit, :account
    assert_equal accounts(:one), credit.account
  end

  test "should belong to conversion" do
    assert_respond_to credit, :conversion
    assert_equal conversions(:signup), credit.conversion
  end

  test "should belong to attribution_model" do
    assert_respond_to credit, :attribution_model
    assert_equal attribution_models(:first_touch), credit.attribution_model
  end

  test "should require channel" do
    credit.channel = nil
    assert_not credit.valid?
    assert_includes credit.errors[:channel], "can't be blank"
  end

  test "should require credit" do
    credit.credit = nil
    assert_not credit.valid?
    assert_includes credit.errors[:credit], "can't be blank"
  end

  test "should require credit between 0 and 1" do
    credit.credit = -0.1
    assert_not credit.valid?
    assert_includes credit.errors[:credit], "must be greater than or equal to 0"

    credit.credit = 1.1
    assert_not credit.valid?
    assert_includes credit.errors[:credit], "must be less than or equal to 1"

    credit.credit = 0
    assert credit.valid?

    credit.credit = 1
    assert credit.valid?

    credit.credit = 0.5
    assert credit.valid?
  end

  test "should allow nil revenue_credit" do
    credit.revenue_credit = nil
    assert credit.valid?
  end

  test "should calculate revenue_credit from conversion revenue" do
    purchase_credit = attribution_credits(:purchase_last_touch)

    assert_equal 99.99, purchase_credit.revenue_credit
    assert_equal 1.0, purchase_credit.credit
  end

  private

  def credit
    @credit ||= attribution_credits(:signup_first_touch)
  end
end
