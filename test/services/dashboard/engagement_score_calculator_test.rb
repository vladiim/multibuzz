# frozen_string_literal: true

require "test_helper"

class Dashboard::EngagementScoreCalculatorTest < ActiveSupport::TestCase
  test "returns score between 0 and 100" do
    score = calculator(identity).call

    assert_operator score[:score], :>=, 0
    assert_operator score[:score], :<=, 100
  end

  test "returns tier label" do
    score = calculator(identity).call

    assert_includes %w[Hot Warm Engaged Cool Cold], score[:tier]
  end

  test "returns component breakdown with recency and frequency" do
    score = calculator(identity).call

    assert score.key?(:components)
    assert score[:components].key?(:recency)
    assert score[:components].key?(:frequency)
  end

  test "returns component breakdown with monetary and breadth" do
    score = calculator(identity).call

    assert score[:components].key?(:monetary)
    assert score[:components].key?(:breadth)
  end

  test "hot tier for highly engaged identity" do
    link_visitor_to_identity(visitors(:one), identity)
    create_sessions_for_visitor(visitors(:one), 15, channels: [ Channels::PAID_SEARCH, Channels::EMAIL, Channels::ORGANIC_SEARCH, Channels::DIRECT, Channels::PAID_SOCIAL ])
    create_conversions_for_identity(identity, 3, revenue: 500.0)
    identity.update!(last_identified_at: Time.current)

    score = calculator(identity).call

    assert_operator score[:score], :>=, 80
    assert_equal "Hot", score[:tier]
  end

  test "cold tier for stale identity with no activity" do
    identity.update!(last_identified_at: 120.days.ago)

    score = calculator(identity).call

    assert_operator score[:score], :<=, 19
    assert_equal "Cold", score[:tier]
  end

  test "recency decays over 90 days" do
    identity.update!(last_identified_at: Time.current)
    recent = calculator(identity).call[:components][:recency]

    identity.update!(last_identified_at: 45.days.ago)
    mid = calculator(identity).call[:components][:recency]

    identity.update!(last_identified_at: 91.days.ago)
    stale = calculator(identity).call[:components][:recency]

    assert_operator recent, :>, mid
    assert_operator mid, :>, stale
    assert_in_delta 0.0, stale, 0.01
  end

  test "frequency capped at 20 sessions" do
    link_visitor_to_identity(visitors(:one), identity)
    create_sessions_for_visitor(visitors(:one), 25)

    score = calculator(identity).call

    assert_in_delta 1.0, score[:components][:frequency], 0.01
  end

  test "monetary is zero when no conversions" do
    score = calculator(identity).call

    assert_in_delta 0.0, score[:components][:monetary], 0.01
  end

  test "breadth increases with distinct channels" do
    link_visitor_to_identity(visitors(:one), identity)
    create_sessions_for_visitor(visitors(:one), 1, channels: [ Channels::PAID_SEARCH ])
    one_channel = calculator(identity).call[:components][:breadth]

    create_sessions_for_visitor(visitors(:one), 3, channels: [ Channels::EMAIL, Channels::ORGANIC_SEARCH, Channels::DIRECT ])
    four_channels = calculator(identity).call[:components][:breadth]

    assert_operator four_channels, :>, one_channel
  end

  test "breadth capped at 5 channels" do
    link_visitor_to_identity(visitors(:one), identity)
    create_sessions_for_visitor(visitors(:one), 7, channels: Channels::ALL.first(7))

    score = calculator(identity).call

    assert_in_delta 1.0, score[:components][:breadth], 0.01
  end

  test "cross-device — counts sessions across all linked visitors" do
    link_visitor_to_identity(visitors(:one), identity)
    link_visitor_to_identity(visitors(:two), identity)
    create_sessions_for_visitor(visitors(:one), 5)
    create_sessions_for_visitor(visitors(:two), 5)

    score = calculator(identity).call

    # 10 created + fixture sessions for both visitors; all count toward frequency
    assert_operator score[:components][:frequency], :>, 0.0
    assert_operator score[:components][:frequency], :<=, 1.0
  end

  private

  def calculator(identity)
    Dashboard::EngagementScoreCalculator.new(account, identity)
  end

  def account = @account ||= accounts(:one)
  def identity = @identity ||= identities(:one)

  def link_visitor_to_identity(visitor, identity)
    visitor.update!(identity: identity)
  end

  def create_sessions_for_visitor(visitor, count, channels: [ Channels::DIRECT ])
    count.times do |i|
      account.sessions.create!(
        visitor: visitor,
        session_id: "sess_score_#{SecureRandom.hex(6)}",
        started_at: (count - i).days.ago,
        channel: channels[i % channels.size]
      )
    end
  end

  def create_conversions_for_identity(identity, count, revenue: nil)
    visitor = identity.visitors.first || visitors(:one).tap { |v| link_visitor_to_identity(v, identity) }

    count.times do |i|
      account.conversions.create!(
        visitor: visitor,
        identity: identity,
        conversion_type: "purchase",
        revenue: revenue,
        converted_at: i.days.ago
      )
    end
  end
end
