module Visitors
  class LookupService < ApplicationService
    def initialize(account, visitor_id, is_test: false, device_fingerprint: nil)
      @account = account
      @visitor_id = visitor_id
      @is_test = is_test
      @device_fingerprint = device_fingerprint
    end

    private

    attr_reader :account, :visitor_id, :is_test, :device_fingerprint

    def run
      return resolution_result if resolution_result.is_a?(Hash) && resolution_result[:errors]

      touch_last_seen
      success_result(resolution_result)
    end

    def resolution_result
      @resolution_result ||= existing_visitor_result || canonical_visitor_result || visitor_not_found_error
    end

    def existing_visitor_result
      return unless existing_visitor

      { visitor: existing_visitor, created: false }
    end

    def canonical_visitor_result
      return unless device_fingerprint.present? && canonical_visitor

      { visitor: canonical_visitor, created: false, canonical: true }
    end

    def visitor_not_found_error
      error_result(["Visitor not found"])
    end

    def existing_visitor
      @existing_visitor ||= account.visitors.find_by(visitor_id: visitor_id)
    end

    def canonical_visitor
      @canonical_visitor ||= recent_session_with_fingerprint&.visitor
    end

    def recent_session_with_fingerprint
      @recent_session_with_fingerprint ||= account.sessions
        .where(device_fingerprint: device_fingerprint)
        .where("sessions.created_at > ?", 30.seconds.ago)
        .order(:created_at)
        .first
    end

    def touch_last_seen
      resolution_result[:visitor].touch_last_seen!
    end
  end
end
