# frozen_string_literal: true

require "test_helper"

module Shopify
  module Handlers
    class OrderPaidTest < ActiveSupport::TestCase
      test "creates conversion with correct attributes" do
        create_visitor_and_session
        result = handler.call

        assert result[:success]
        assert conversion.prefix_id.present?

        assert_equal Shopify::CONVERSION_TYPE_PURCHASE, conversion.conversion_type
        assert_equal 99.99, conversion.revenue.to_f
        assert_equal "USD", conversion.currency
        assert_equal visitor.id, conversion.visitor_id
        assert_equal session.id, conversion.session_id
      end

      test "stores shopify properties in conversion" do
        create_visitor_and_session
        handler.call

        assert_equal "12345", conversion.properties[Shopify::PROP_ORDER_ID]
        assert_equal 1001, conversion.properties[Shopify::PROP_ORDER_NUMBER]
        assert_equal "customer@example.com", conversion.properties[Shopify::PROP_CUSTOMER_EMAIL]
      end

      test "returns error when visitor not found" do
        result = handler(visitor_id: "nonexistent").call

        refute result[:success]
        assert_includes result[:error], "Visitor not found for visitor_id"
      end

      test "falls back to email-based visitor lookup when no note_attributes" do
        identity = account.identities.create!(
          external_id: "shopify_user",
          traits: { "email" => "customer@example.com" },
          first_identified_at: 1.day.ago,
          last_identified_at: 1.hour.ago
        )
        email_visitor = account.visitors.create!(
          visitor_id: SecureRandom.hex(32),
          identity: identity,
          first_seen_at: 1.day.ago,
          last_seen_at: 1.hour.ago
        )
        email_session = email_visitor.sessions.create!(
          account: account,
          session_id: SecureRandom.hex(32),
          started_at: 1.hour.ago,
          initial_utm: {},
          initial_referrer: nil
        )

        payload_without_note = {
          id: 12345,
          order_number: 1001,
          total_price: "99.99",
          currency: "USD",
          customer: { email: "customer@example.com" },
          note_attributes: []
        }

        result = Handlers::OrderPaid.new(account, payload_without_note).call

        assert result[:success]
        assert_equal email_visitor.id, conversion.visitor_id
        assert_equal email_session.id, conversion.session_id
      end

      test "uses latest session for conversion" do
        create_visitor_and_session
        older_session = visitor.sessions.create!(
          account: account,
          session_id: SecureRandom.hex(32),
          started_at: 2.hours.ago,
          initial_utm: {},
          initial_referrer: nil
        )

        handler.call

        assert_equal session.id, conversion.session_id
        refute_equal older_session.id, conversion.session_id
      end

      test "handles missing currency by defaulting to USD" do
        create_visitor_and_session
        payload_without_currency = payload.except(:currency)

        Handlers::OrderPaid.new(account, payload_without_currency).call

        assert_equal "USD", conversion.currency
      end

      private

      def handler(visitor_id: self.visitor_id)
        @handler = nil if visitor_id != self.visitor_id
        @handler ||= Handlers::OrderPaid.new(account, payload(visitor_id: visitor_id))
      end

      def payload(visitor_id: self.visitor_id)
        {
          id: 12345,
          order_number: 1001,
          total_price: "99.99",
          currency: "USD",
          customer: { email: "customer@example.com" },
          note_attributes: [
            { name: Shopify::NOTE_ATTR_VISITOR_ID, value: visitor_id },
            { name: Shopify::NOTE_ATTR_SESSION_ID, value: session_id }
          ]
        }
      end

      def account
        @account ||= accounts(:one)
      end

      def create_visitor_and_session
        visitor
        session
      end

      def visitor_id
        @visitor_id ||= SecureRandom.hex(32)
      end

      def session_id
        @session_id ||= SecureRandom.hex(32)
      end

      def visitor
        @visitor ||= account.visitors.create!(
          visitor_id: visitor_id,
          first_seen_at: 1.hour.ago,
          last_seen_at: Time.current
        )
      end

      def session
        @session ||= visitor.sessions.create!(
          account: account,
          session_id: session_id,
          started_at: 30.minutes.ago,
          initial_utm: { "utm_source" => "google" },
          initial_referrer: "https://google.com"
        )
      end

      def conversion
        Conversion.last
      end
    end
  end
end
