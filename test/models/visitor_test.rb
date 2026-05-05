# frozen_string_literal: true

require "test_helper"

class VisitorTest < ActiveSupport::TestCase
  test "should be valid with valid attributes" do
    assert_predicate visitor, :valid?
  end

  test "should belong to account" do
    assert_equal account, visitor.account
  end

  test "should require account" do
    visitor.account = nil

    assert_not visitor.valid?
    assert_includes visitor.errors[:account], "must exist"
  end

  test "should require visitor_id" do
    visitor.visitor_id = nil

    assert_not visitor.valid?
    assert_includes visitor.errors[:visitor_id], "can't be blank"
  end

  test "should require unique visitor_id per account" do
    duplicate = Visitor.new(
      account: account,
      visitor_id: visitor.visitor_id
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:visitor_id], "has already been taken"
  end

  test "should allow same visitor_id across different accounts" do
    other_visitor = Visitor.new(
      account: other_account,
      visitor_id: visitor.visitor_id
    )

    assert_predicate other_visitor, :valid?
  end

  test "should validate visitor_id format" do
    valid_ids = %w[
      abc123xyz789
      visitor_12345
      vis_abc123
      a1b2c3d4e5f6
    ]

    valid_ids.each do |id|
      visitor.visitor_id = id

      assert_predicate visitor, :valid?, "#{id} should be valid"
    end
  end

  test "should accept visitor_ids with dots colons and single characters" do
    valid_ids = %w[
      x
      a1
      ga4.1234567890.1234567890
      segment:anonymous:abc123
      user-123_v2
    ]

    valid_ids.each do |id|
      visitor.visitor_id = id

      assert_predicate visitor, :valid?, "#{id} should be valid"
    end
  end

  test "should reject invalid visitor_id formats" do
    invalid_ids = [
      "abc 123",           # spaces
      "abc@123",           # @ symbol
      "abc#123",           # hash symbol
      ""                   # empty string
    ]

    invalid_ids.each do |id|
      visitor.visitor_id = id

      assert_not visitor.valid?, "#{id} should be invalid"
    end
  end

  test "should reject visitor_id exceeding max length" do
    visitor.visitor_id = "a" * 256

    assert_not visitor.valid?
  end

  test "should have many sessions" do
    assert_respond_to visitor, :sessions
  end

  test "should have many events" do
    assert_respond_to visitor, :events
  end

  test "should store traits as jsonb" do
    visitor.update!(traits: { browser: "Chrome", os: "macOS" })
    visitor.reload

    assert_equal "Chrome", visitor.traits["browser"]
    assert_equal "macOS", visitor.traits["os"]
  end

  test "should track first_seen_at on creation" do
    new_visitor = Visitor.create!(
      account: account,
      visitor_id: "new_visitor_123"
    )

    assert_predicate new_visitor.first_seen_at, :present?
    assert_in_delta Time.current, new_visitor.first_seen_at, 1.second
  end

  test "should track last_seen_at on creation" do
    new_visitor = Visitor.create!(
      account: account,
      visitor_id: "new_visitor_456"
    )

    assert_predicate new_visitor.last_seen_at, :present?
    assert_in_delta Time.current, new_visitor.last_seen_at, 1.second
  end

  test "should update last_seen_at" do
    old_time = 1.day.ago
    visitor.update_column(:last_seen_at, old_time)

    visitor.touch_last_seen!

    assert_in_delta Time.current, visitor.last_seen_at, 1.second
    assert_not_equal old_time, visitor.last_seen_at
  end

  test "should scope recent visitors" do
    recent = Visitor.recent

    assert_includes recent, visitor
  end

  # --- normalize_id ---

  test "normalize_id strips any number of leading and trailing double-quotes" do
    canonical = "dc8e02e6eacea041129965931c82c60b6d8b0043eff135cf20d2f95f7779a794"
    [ 0, 1, 2, 5, 10, 19, 100 ].each do |count|
      wrapped = ('"' * count) + canonical + ('"' * count)

      assert_equal canonical, Visitor.normalize_id(wrapped),
        "expected #{count} symmetric leading/trailing quotes to strip to canonical"
    end
  end

  test "normalize_id strips asymmetric leading and trailing double-quotes" do
    canonical = "abc123"

    assert_equal canonical, Visitor.normalize_id('"""' + canonical)
    assert_equal canonical, Visitor.normalize_id(canonical + '""""""""')
    assert_equal canonical, Visitor.normalize_id('"' + canonical + '""""')
  end

  test "normalize_id leaves unquoted ids untouched" do
    assert_equal "abc123", Visitor.normalize_id("abc123")
    assert_equal "vis_abc.123:xyz-9", Visitor.normalize_id("vis_abc.123:xyz-9")
  end

  test "normalize_id does not strip embedded quotes" do
    assert_equal 'a"b', Visitor.normalize_id('a"b')
    assert_equal 'a"b', Visitor.normalize_id('"""a"b"""')
  end

  test "normalize_id is safe for nil and blank values" do
    assert_nil Visitor.normalize_id(nil)
    assert_equal "", Visitor.normalize_id("")
    assert_equal "", Visitor.normalize_id('""""')
  end

  private

  def visitor
    @visitor ||= visitors(:one)
  end

  def account
    @account ||= accounts(:one)
  end

  def other_account
    @other_account ||= accounts(:two)
  end
end
