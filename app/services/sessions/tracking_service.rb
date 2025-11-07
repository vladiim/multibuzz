module Sessions
  class TrackingService
    def initialize(account)
      @account = account
    end

    def call(session_id, visitor)
      session = account.sessions.active.find_by(session_id: session_id, visitor: visitor)
      created = session.nil?

      session ||= account.sessions.create(session_id: session_id, visitor: visitor)

      return error_result(session) unless session.persisted?

      session.increment_page_views! unless created
      success_result(session, created)
    end

    private

    attr_reader :account

    def success_result(session, created)
      {
        success: true,
        session: session,
        created: created
      }
    end

    def error_result(session)
      {
        success: false,
        errors: session.errors.full_messages
      }
    end
  end
end
