# frozen_string_literal: true

require "test_helper"

class Dashboard::ConversionDetailQueryTest < ActiveSupport::TestCase
  setup do
    Conversion.where(account: account).where.not(
      id: [ conversions(:signup).id, conversions(:purchase).id ]
    ).delete_all
  end

  test "returns conversion with basic attributes" do
    result = query.call(conversion.prefix_id)

    assert result
    assert_equal conversion.id, result.id
    assert_equal "purchase", result.conversion_type
  end

  test "returns conversion revenue" do
    result = query.call(conversion.prefix_id)

    assert_in_delta 99.99, result.revenue.to_f
  end

  test "eager loads visitor" do
    result = query.call(conversion.prefix_id)

    assert result.visitor
    assert_equal visitors(:two).id, result.visitor.id
    assert_no_queries { result.visitor.visitor_id }
  end

  test "eager loads identity when present" do
    conversion.update!(identity: identities(:one))

    result = query.call(conversion.prefix_id)

    assert result.identity
    assert_equal identities(:one).id, result.identity.id
    assert_no_queries { result.identity.external_id }
  end

  test "returns nil identity when not linked" do
    result = query.call(conversion.prefix_id)

    assert_nil result.identity
  end

  test "eager loads attribution credits" do
    result = query.call(conversion.prefix_id)

    assert_predicate result.attribution_credits, :any?
    assert_no_queries { result.attribution_credits.first.channel }
  end

  test "loads journey sessions from journey_session_ids in order" do
    s1 = create_session(started_at: 10.days.ago, channel: Channels::PAID_SEARCH)
    s2 = create_session(started_at: 5.days.ago, channel: Channels::ORGANIC_SOCIAL)
    s3 = create_session(started_at: 1.day.ago, channel: Channels::DIRECT)
    conversion.update_column(:journey_session_ids, [ s1.id, s2.id, s3.id ])

    result = query.call(conversion.prefix_id)

    assert_equal 3, result.journey_sessions.size
    assert_equal [ s1.id, s2.id, s3.id ], result.journey_sessions.map(&:id)
  end

  test "returns empty journey sessions when journey_session_ids is empty" do
    conversion.update_column(:journey_session_ids, [])

    result = query.call(conversion.prefix_id)

    assert_equal [], result.journey_sessions
  end

  test "returns nil for other accounts conversion" do
    other_conversion = conversions(:trial_start)

    result = query.call(other_conversion.prefix_id)

    assert_nil result
  end

  test "returns nil for nonexistent prefix_id" do
    result = query.call("conv_nonexistent")

    assert_nil result
  end

  test "computes time gaps between journey sessions" do
    s1 = create_session(started_at: 10.days.ago, channel: Channels::PAID_SEARCH)
    s2 = create_session(started_at: 7.days.ago, channel: Channels::EMAIL)
    conversion.update_column(:journey_session_ids, [ s1.id, s2.id ])

    result = query.call(conversion.prefix_id)
    gaps = result.journey_time_gaps

    assert_equal 1, gaps.size
    assert_in_delta 3.0, gaps.first, 0.1
  end

  test "computes total time to convert" do
    s1 = create_session(started_at: 10.days.ago, channel: Channels::PAID_SEARCH)
    conversion.update_column(:journey_session_ids, [ s1.id ])

    result = query.call(conversion.prefix_id)
    expected_days = (conversion.converted_at - s1.started_at) / 1.day

    assert_in_delta expected_days, result.days_to_convert, 0.1
  end

  private

  def query = @query ||= Dashboard::ConversionDetailQuery.new(account)
  def account = @account ||= accounts(:one)
  def conversion = @conversion ||= conversions(:purchase)

  def create_session(started_at:, channel:)
    account.sessions.create!(
      visitor: visitors(:one),
      session_id: "sess_#{SecureRandom.hex(8)}",
      started_at: started_at,
      channel: channel
    )
  end

  def assert_no_queries(&block)
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless payload[:name]&.include?("SCHEMA") || payload[:name] == "CACHE"
    }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)

    assert_equal 0, count, "Expected no queries but got #{count}"
  end
end
