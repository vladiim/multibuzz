module Sessions
  class TrackingService < ApplicationService
    def initialize(account, session_id, visitor)
      @account = account
      @session_id = session_id
      @visitor = visitor
    end

    private

    attr_reader :account, :session_id, :visitor

    def run
      created = session.nil?

      unless session
        @session = account.sessions.create(session_id: session_id, visitor: visitor)
        return error_result(session.errors.full_messages) unless session.persisted?
        created = true
      end

      # Increment page views for every page view event
      session.increment_page_views!

      success_result(session: session, created: created)
    end

    def session
      @session ||= account.sessions.active.find_by(session_id: session_id, visitor: visitor)
    end
  end
end
