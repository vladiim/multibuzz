require "test_helper"

class ConversionTest < ActiveSupport::TestCase
  test "should belong to account" do
    assert_respond_to conversion, :account
    assert_equal accounts(:one), conversion.account
  end

  test "should belong to visitor" do
    assert_respond_to conversion, :visitor
    assert_equal visitors(:one), conversion.visitor
  end

  test "should have many attribution credits" do
    assert_respond_to conversion, :attribution_credits
  end

  test "should have prefixed id" do
    assert conversion.prefix_id.start_with?("conv_")
  end

  test "should require conversion_type" do
    conversion.conversion_type = nil
    assert_not conversion.valid?
    assert_includes conversion.errors[:conversion_type], "can't be blank"
  end

  test "should require converted_at" do
    conversion.converted_at = nil
    assert_not conversion.valid?
    assert_includes conversion.errors[:converted_at], "can't be blank"
  end

  test "should allow user-defined conversion types" do
    conversion.conversion_type = "custom_event"
    assert conversion.valid?

    conversion.conversion_type = "any_string_the_user_wants"
    assert conversion.valid?
  end

  test "should allow nil revenue" do
    conversion.revenue = nil
    assert conversion.valid?
  end

  test "should require non-negative revenue when present" do
    conversion.revenue = 0
    assert conversion.valid?, "Zero revenue should be valid"

    conversion.revenue = -10
    assert_not conversion.valid?
    assert_includes conversion.errors[:revenue], "must be greater than or equal to 0"

    conversion.revenue = 0.01
    assert conversion.valid?
  end

  test "should store journey session ids as array" do
    assert_equal [1], conversion.journey_session_ids

    conversion.journey_session_ids = [1, 2, 3]
    assert conversion.save
    conversion.reload
    assert_equal [1, 2, 3], conversion.journey_session_ids
  end

  # ==========================================
  # Acquisition attribution tests
  # ==========================================

  test "should optionally belong to identity" do
    assert_respond_to conversion, :identity
    assert_nil conversion.identity

    conversion.identity = identity
    assert conversion.valid?
    assert_equal identity, conversion.identity
  end

  test "should have is_acquisition boolean defaulting to false" do
    new_conversion = Conversion.new(
      account: account,
      visitor: visitor,
      conversion_type: "signup",
      converted_at: Time.current
    )
    assert_equal false, new_conversion.is_acquisition
  end

  test "inherit_acquisition? returns false by default" do
    assert_equal false, conversion.inherit_acquisition?
  end

  test "inherit_acquisition? returns true when set to true" do
    conversion.inherit_acquisition = true
    assert_equal true, conversion.inherit_acquisition?
  end

  test "inherit_acquisition? returns true when set to string true" do
    conversion.inherit_acquisition = "true"
    assert_equal true, conversion.inherit_acquisition?
  end

  test "inherit_acquisition? returns false when set to false" do
    conversion.inherit_acquisition = false
    assert_equal false, conversion.inherit_acquisition?
  end

  test "inherit_acquisition? returns false when set to nil" do
    conversion.inherit_acquisition = nil
    assert_equal false, conversion.inherit_acquisition?
  end

  test "is_acquisition requires identity when true" do
    conversion.is_acquisition = true
    conversion.identity = nil
    assert_not conversion.valid?
    assert_includes conversion.errors[:identity], "is required when marking as acquisition"
  end

  test "is_acquisition allowed without identity when false" do
    conversion.is_acquisition = false
    conversion.identity = nil
    assert conversion.valid?
  end

  test "is_acquisition valid with identity when true" do
    conversion.is_acquisition = true
    conversion.identity = identity
    assert conversion.valid?
  end

  private

  def identity
    @identity ||= identities(:one)
  end

  def account
    @account ||= accounts(:one)
  end

  def visitor
    @visitor ||= visitors(:one)
  end

  def conversion
    @conversion ||= conversions(:signup)
  end
end
