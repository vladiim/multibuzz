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

      touch_last_seen_unless_created
      increment_usage_if_created

      success_result(resolution_result)
    end

    def resolution_result
      @resolution_result ||= existing_visitor_result || canonical_visitor_result || create_visitor_result
    end

    def existing_visitor_result
      return unless existing_visitor

      { visitor: existing_visitor, created: false }
    end

    def canonical_visitor_result
      return unless device_fingerprint.present? && canonical_visitor

      { visitor: canonical_visitor, created: false, canonical: true }
    end

    def create_visitor_result
      new_visitor = account.visitors.create(visitor_id: visitor_id, is_test: is_test)
      return error_result(new_visitor.errors.full_messages) unless new_visitor.persisted?

      { visitor: new_visitor, created: true }
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

    def touch_last_seen_unless_created
      resolution_result[:visitor].touch_last_seen! unless resolution_result[:created]
    end

    def increment_usage_if_created
      Billing::UsageCounter.new(account).increment! if resolution_result[:created]
    end
  end
end
