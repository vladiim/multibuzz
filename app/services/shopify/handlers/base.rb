# frozen_string_literal: true

module Shopify
  module Handlers
    class Base
      def initialize(account, payload)
        @account = account
        @payload = payload
      end

      def call
        raise NotImplementedError, "Subclasses must implement #call"
      end

      private

      attr_reader :account, :payload

      def visitor_id_from_note
        extract_note_attribute(Shopify::NOTE_ATTR_VISITOR_ID)
      end

      def session_id_from_note
        extract_note_attribute(Shopify::NOTE_ATTR_SESSION_ID)
      end

      def extract_note_attribute(name)
        note_attributes = payload[:note_attributes] || []
        note_attributes.find { |attr| attr[:name] == name }&.dig(:value)
      end

      # Primary lookup: cart note attributes
      # Fallback: email-based identity lookup (for "Buy it now" flows)
      def visitor
        @visitor ||= visitor_from_note || visitor_from_email
      end

      def visitor_from_note
        return unless visitor_id_from_note.present?

        account.visitors.find_by(visitor_id: visitor_id_from_note)
      end

      def visitor_from_email
        return unless customer_email.present?

        identity_by_email&.visitors&.order(created_at: :desc)&.first
      end

      def identity_by_email
        account.identities.find_by("traits->>'email' = ?", customer_email)
      end

      def customer_email
        payload.dig(:customer, :email)
      end

      def latest_session
        return session_from_note if session_from_note
        visitor&.sessions&.order(started_at: :desc)&.first
      end

      def session_from_note
        return unless session_id_from_note.present?

        @session_from_note ||= visitor&.sessions&.find_by(session_id: session_id_from_note)
      end
    end
  end
end
