# frozen_string_literal: true

module Attribution
  class CrossDeviceJourneyBuilder
    include BurstDeduplication

    def initialize(identity:, converted_at:, lookback_days:)
      @identity = identity
      @converted_at = converted_at
      @lookback_days = lookback_days
    end

    def call
      collapse_burst_sessions(touchpoints)
    end

    private

    attr_reader :identity, :converted_at, :lookback_days

    def touchpoints
      @touchpoints ||= sessions_in_window
        .where.not(channel: nil)
        .order(started_at: :asc)
        .map { |session| build_touchpoint(session) }
    end

    def sessions_in_window
      identity
        .account
        .sessions
        .qualified
        .where(visitor: identity.visitors)
        .where("started_at >= ?", lookback_window_start)
        .where("started_at <= ?", converted_at)
    end

    def lookback_window_start
      @lookback_window_start ||= converted_at - lookback_days.days
    end

    def build_touchpoint(session)
      {
        session_id: session.id,
        channel: session.channel,
        occurred_at: session.started_at
      }
    end
  end
end
