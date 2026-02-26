# frozen_string_literal: true

module Sessions
  class ResolutionService
    SESSION_TIMEOUT = 30.minutes
    RACE_WINDOW = 5.minutes
    FINGERPRINT_LENGTH = 32

    def initialize(account:, visitor_id:, ip:, user_agent:, identifier: nil)
      @account = account
      @visitor_id = visitor_id
      @ip = ip
      @user_agent = user_agent
      @identifier = identifier
    end

    def call
      link_visitor_to_identity_if_needed
      resolved_session&.session_id || generate_deterministic_id
    end

    private

    attr_reader :account, :visitor_id, :ip, :user_agent, :identifier

    def resolved_session
      identity_session || visitor_session
    end

    def visitor_session
      return unless visitor

      scope = account.sessions
        .where(visitor_id: visitor.id)
        .where(ended_at: nil)
        .where("last_activity_at > ?", SESSION_TIMEOUT.ago)
        .order(last_activity_at: :desc)

      scope.where(device_fingerprint: [ device_fingerprint, nil ]).first || scope.first
    end

    def identity_session
      return unless identifier.present? && identity

      account.sessions
        .where(visitor_id: identity_visitor_ids)
        .where(ended_at: nil)
        .where("last_activity_at > ?", SESSION_TIMEOUT.ago)
        .order(last_activity_at: :desc)
        .first
    end

    def identity
      return @identity if defined?(@identity)

      @identity = find_identity_by_identifier
    end

    def find_identity_by_identifier
      external_id = identifier_external_id
      return unless external_id.present?

      account.identities.find_by(external_id: external_id)
    end

    def identifier_external_id
      return identifier[:email] if identifier[:email].present?
      return identifier["email"] if identifier["email"].present?
      return identifier[:user_id] if identifier[:user_id].present?
      return identifier["user_id"] if identifier["user_id"].present?

      identifier.values.first
    end

    def identity_visitor_ids
      identity.visitors.pluck(:id)
    end

    def link_visitor_to_identity_if_needed
      return unless identifier.present? && identity && visitor
      return if visitor.identity_id == identity.id

      visitor.update!(identity: identity)
    end

    def visitor
      @visitor ||= account.visitors.find_by(visitor_id: visitor_id)
    end

    def device_fingerprint
      @device_fingerprint ||= Digest::SHA256.hexdigest("#{ip}|#{user_agent}")[0, FINGERPRINT_LENGTH]
    end

    def generate_deterministic_id
      return generate_deterministic_id_without_visitor unless visitor

      time_bucket = Time.current.to_i / RACE_WINDOW.to_i
      Digest::SHA256.hexdigest("#{visitor_id}_#{device_fingerprint}_#{time_bucket}")[0, FINGERPRINT_LENGTH]
    end

    def generate_deterministic_id_without_visitor
      time_bucket = Time.current.to_i / RACE_WINDOW.to_i
      Digest::SHA256.hexdigest("#{visitor_id}_#{device_fingerprint}_#{time_bucket}")[0, FINGERPRINT_LENGTH]
    end
  end
end
