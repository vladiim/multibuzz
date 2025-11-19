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

  test "should require positive revenue when present" do
    conversion.revenue = 0
    assert_not conversion.valid?
    assert_includes conversion.errors[:revenue], "must be greater than 0"

    conversion.revenue = -10
    assert_not conversion.valid?

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

  private

  def conversion
    @conversion ||= conversions(:signup)
  end
end
