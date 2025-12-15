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

      def visitor_id
        extract_note_attribute(Shopify::NOTE_ATTR_VISITOR_ID)
      end

      def session_id
        extract_note_attribute(Shopify::NOTE_ATTR_SESSION_ID)
      end

      def extract_note_attribute(name)
        note_attributes = payload[:note_attributes] || []
        note_attributes.find { |attr| attr[:name] == name }&.dig(:value)
      end

      def visitor
        @visitor ||= account.visitors.find_by(visitor_id: visitor_id)
      end

      def latest_session
        visitor&.sessions&.order(started_at: :desc)&.first
      end
    end
  end
end
