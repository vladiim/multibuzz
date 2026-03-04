# frozen_string_literal: true

require "test_helper"

class Dashboard::IdentityDetailQueryTest < ActiveSupport::TestCase
  test "returns identity with basic attributes" do
    result = query.call(identity.prefix_id)

    assert result
    assert_equal identity.id, result.id
    assert_equal "fixture_user_001", result.external_id
  end

  test "eager loads visitors" do
    visitors(:one).update!(identity: identity)

    result = query.call(identity.prefix_id)

    assert_predicate result.visitors, :any?
    assert_no_queries { result.visitors.first.visitor_id }
  end

  test "eager loads conversions" do
    account.conversions.create!(
      visitor: visitors(:one),
      identity: identity,
      conversion_type: "purchase",
      revenue: 100,
      converted_at: 1.day.ago
    )

    result = query.call(identity.prefix_id)

    assert_predicate result.conversions, :any?
    assert_no_queries { result.conversions.first.conversion_type }
  end

  test "returns nil for other accounts identity" do
    other = identities(:other_account_identity)

    result = query.call(other.prefix_id)

    assert_nil result
  end

  test "returns nil for nonexistent prefix_id" do
    result = query.call("idt_nonexistent")

    assert_nil result
  end

  test "computes channel breakdown from linked visitors sessions" do
    visitors(:one).update!(identity: identity)
    create_sessions_with_channels

    result = query.call(identity.prefix_id)
    breakdown = result.channel_breakdown

    assert_kind_of Hash, breakdown
    assert breakdown.key?(Channels::PAID_SEARCH)
    assert breakdown.key?(Channels::EMAIL)
  end

  test "computes total revenue from conversions" do
    account.conversions.create!(
      visitor: visitors(:one), identity: identity,
      conversion_type: "purchase", revenue: 100, converted_at: 1.day.ago
    )
    account.conversions.create!(
      visitor: visitors(:one), identity: identity,
      conversion_type: "purchase", revenue: 50, converted_at: 2.days.ago
    )

    result = query.call(identity.prefix_id)

    assert_in_delta 150.0, result.total_revenue, 0.01
  end

  test "channel breakdown scoped to linked visitors only" do
    visitors(:one).update!(identity: identity)
    # Create session for visitor NOT linked to this identity
    account.sessions.create!(
      visitor: visitors(:two),
      session_id: "sess_unlinked_#{SecureRandom.hex(4)}",
      started_at: 1.day.ago,
      channel: Channels::AFFILIATE
    )

    result = query.call(identity.prefix_id)

    refute result.channel_breakdown.key?(Channels::AFFILIATE)
  end

  private

  def query = @query ||= Dashboard::IdentityDetailQuery.new(account)
  def account = @account ||= accounts(:one)
  def identity = @identity ||= identities(:one)

  def create_sessions_with_channels
    [ Channels::PAID_SEARCH, Channels::PAID_SEARCH, Channels::EMAIL ].each_with_index do |channel, i|
      account.sessions.create!(
        visitor: visitors(:one),
        session_id: "sess_idt_#{SecureRandom.hex(4)}_#{i}",
        started_at: (3 - i).days.ago,
        channel: channel
      )
    end
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
