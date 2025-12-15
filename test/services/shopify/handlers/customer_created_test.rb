# frozen_string_literal: true

require "test_helper"

module Shopify
  module Handlers
    class CustomerCreatedTest < ActiveSupport::TestCase
      test "creates identity and links visitor" do
        create_visitor

        result = handler.call

        assert result[:success]
        assert identity.prefix_id.present?
        assert_equal identity.id, visitor.reload.identity_id
      end

      test "stores customer traits in identity" do
        create_visitor

        handler.call

        assert_equal "customer@example.com", identity.traits["email"]
        assert_equal "John", identity.traits["first_name"]
        assert_equal "Doe", identity.traits["last_name"]
      end

      test "uses shopify customer id as external_id" do
        create_visitor

        handler.call

        assert_equal "67890", identity.external_id
      end

      test "returns error when visitor not found" do
        result = handler(visitor_id: "nonexistent").call

        refute result[:success]
        assert_equal "Visitor not found", result[:error]
      end

      test "finds existing identity by external_id" do
        create_visitor
        existing_identity = account.identities.create!(
          external_id: "67890",
          first_identified_at: 1.day.ago,
          last_identified_at: 1.day.ago,
          traits: { email: "old@example.com" }
        )

        assert_no_difference "Identity.count" do
          handler.call
        end

        assert_equal existing_identity.id, visitor.reload.identity_id
      end

      private

      def handler(visitor_id: self.visitor_id)
        @handler = nil if visitor_id != self.visitor_id
        @handler ||= Handlers::CustomerCreated.new(account, payload(visitor_id: visitor_id))
      end

      def payload(visitor_id: self.visitor_id)
        {
          id: 67890,
          email: "customer@example.com",
          first_name: "John",
          last_name: "Doe",
          note_attributes: [
            { name: Shopify::NOTE_ATTR_VISITOR_ID, value: visitor_id }
          ]
        }
      end

      def account
        @account ||= accounts(:one)
      end

      def visitor_id
        @visitor_id ||= SecureRandom.hex(32)
      end

      def create_visitor
        visitor
      end

      def visitor
        @visitor ||= account.visitors.create!(
          visitor_id: visitor_id,
          first_seen_at: 1.hour.ago,
          last_seen_at: Time.current
        )
      end

      def identity
        Identity.last
      end
    end
  end
end
