module Sessions
  class ResolutionService
    SESSION_TIMEOUT = 30.minutes
    RACE_WINDOW = 5.minutes
    FINGERPRINT_LENGTH = 32

    def initialize(account:, visitor_id:, ip:, user_agent:)
      @account = account
      @visitor_id = visitor_id
      @ip = ip
      @user_agent = user_agent
    end

    def call
      return generate_deterministic_id unless visitor

      active_session&.session_id || generate_deterministic_id
    end

    private

    attr_reader :account, :visitor_id, :ip, :user_agent

    def visitor
      @visitor ||= account.visitors.find_by(visitor_id: visitor_id)
    end

    def active_session
      @active_session ||= account.sessions
        .where(visitor_id: visitor.id)
        .where(device_fingerprint: device_fingerprint)
        .where(ended_at: nil)
        .where("last_activity_at > ?", SESSION_TIMEOUT.ago)
        .order(last_activity_at: :desc)
        .first
    end

    def device_fingerprint
      @device_fingerprint ||= Digest::SHA256.hexdigest("#{ip}|#{user_agent}")[0, FINGERPRINT_LENGTH]
    end

    def generate_deterministic_id
      time_bucket = Time.current.to_i / RACE_WINDOW.to_i
      Digest::SHA256.hexdigest("#{visitor_id}_#{device_fingerprint}_#{time_bucket}")[0, FINGERPRINT_LENGTH]
    end
  end
end
