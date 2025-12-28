module Sessions
  class TrackingService < ApplicationService
    def initialize(account, session_id, visitor, event_timestamp: nil, is_test: false)
      @account = account
      @session_id = session_id
      @visitor = visitor
      @event_timestamp = event_timestamp
      @is_test = is_test
    end

    private

    attr_reader :account, :session_id, :visitor, :event_timestamp, :is_test

    def run
      created = session.nil?

      unless session
        @session = account.sessions.create(
          session_id: session_id,
          visitor: visitor,
          started_at: event_timestamp,
          is_test: is_test
        )
        return error_result(session.errors.full_messages) unless session.persisted?
        created = true
      end

      session.increment_page_views!
      increment_usage! if created

      success_result(session: session, created: created)
    end

    def session
      @session ||= account.sessions.active.find_by(session_id: session_id, visitor: visitor)
    end

    def increment_usage!
      Billing::UsageCounter.new(account).increment!
    end
  end
end
