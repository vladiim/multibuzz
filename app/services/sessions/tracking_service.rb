module Sessions
  class TrackingService < ApplicationService
    def initialize(account, session_id, visitor, event_timestamp: nil, is_test: false, device_fingerprint: nil)
      @account = account
      @session_id = session_id
      @visitor = visitor
      @event_timestamp = event_timestamp
      @is_test = is_test
      @device_fingerprint = device_fingerprint
    end

    private

    attr_reader :account, :session_id, :visitor, :event_timestamp, :is_test, :device_fingerprint

    def run
      created = session.nil?

      unless session
        @session = account.sessions.create(
          session_id: session_id,
          visitor: visitor,
          started_at: event_timestamp,
          is_test: is_test,
          device_fingerprint: device_fingerprint,
          last_activity_at: event_timestamp
        )
        return error_result(session.errors.full_messages) unless session.persisted?
        created = true
      end

      session.update!(last_activity_at: Time.current) unless created
      session.increment_page_views!
      increment_usage! if created

      success_result(session: session, created: created)
    end

    def session
      @session ||= find_existing_session
    end

    def find_existing_session
      existing_for_visitor || existing_cross_device
    end

    def existing_for_visitor
      account.sessions.active.find_by(session_id: session_id, visitor: visitor)
    end

    def existing_cross_device
      account.sessions.active.find_by(session_id: session_id)
    end

    def increment_usage!
      Billing::UsageCounter.new(account).increment!
    end
  end
end
