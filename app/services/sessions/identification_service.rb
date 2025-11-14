module Sessions
  class IdentificationService
    COOKIE_NAME = "_multibuzz_sid"
    SESSION_TIMEOUT = 30.minutes

    def initialize(request, account, visitor_id)
      @request = request
      @account = account
      @visitor_id = visitor_id
    end

    def call
      end_expired_session if session_expired?
      { session_id: session_id, set_cookie: set_cookie_header, created: session_created? }
    end

    private

    attr_reader :request, :account, :visitor_id

    def session_id
      @session_id ||= extract_session_id || generate_session_id
    end

    def extract_session_id
      return nil unless existing_session_id.present?
      return nil if session_expired?

      existing_session_id
    end

    def existing_session_id
      @existing_session_id ||= request.cookies[COOKIE_NAME]
    end

    def generate_session_id
      SecureRandom.hex(32)
    end

    def session_created?
      extract_session_id.nil?
    end

    def session_expired?
      return false unless existing_session&.started_at

      existing_session.started_at < SESSION_TIMEOUT.ago
    end

    def existing_session
      @existing_session ||= account.sessions.find_by(
        session_id: existing_session_id,
        visitor_id: visitor_id
      )
    end

    def end_expired_session
      existing_session&.end_session!
    end

    def set_cookie_header
      @set_cookie_header ||= build_set_cookie
    end

    def build_set_cookie
      "#{COOKIE_NAME}=#{session_id}; " \
      "Max-Age=#{SESSION_TIMEOUT.to_i}; " \
      "Path=/; " \
      "#{httponly_flag}" \
      "#{secure_flag}" \
      "SameSite=Lax"
    end

    def httponly_flag
      "HttpOnly; "
    end

    def secure_flag
      Rails.env.production? ? "Secure; " : ""
    end
  end
end
