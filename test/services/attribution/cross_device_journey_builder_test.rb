# frozen_string_literal: true

require "test_helper"

module Attribution
  class CrossDeviceJourneyBuilderTest < ActiveSupport::TestCase
    test "should exclude suspect sessions from cross-device journey" do
      real = create_session(days_ago: 5, channel: "email")
      suspect = create_session(days_ago: 3, channel: "direct", suspect: true)

      touchpoints = service.call

      session_ids = touchpoints.map { |t| t[:session_id] }

      assert_includes session_ids, real.id
      assert_not_includes session_ids, suspect.id
    end

    test "should only include non-suspect sessions" do
      create_session(days_ago: 7, channel: "paid_search", suspect: true)
      real = create_session(days_ago: 3, channel: "organic_search")

      touchpoints = service.call

      assert_equal 1, touchpoints.size
      assert_equal real.id, touchpoints[0][:session_id]
    end

    private

    def service
      @service ||= Attribution::CrossDeviceJourneyBuilder.new(
        identity: identity,
        converted_at: Time.current,
        lookback_days: 30
      )
    end

    def identity
      @identity ||= identities(:one).tap do |idt|
        visitor.update!(identity: idt)
      end
    end

    def visitor
      @visitor ||= visitors(:one)
    end

    def create_session(days_ago:, channel:, suspect: false)
      Session.create!(
        account: visitor.account,
        visitor: visitor,
        session_id: SecureRandom.hex(16),
        started_at: days_ago.days.ago,
        channel: channel,
        suspect: suspect
      )
    end
  end
end
