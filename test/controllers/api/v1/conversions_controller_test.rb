# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ConversionsControllerTest < ActionDispatch::IntegrationTest
      def setup
        Rails.cache.clear
      end

      # ==========================================
      # Event-based conversion tests
      # ==========================================

      test "creates conversion with event_id" do
        post api_v1_conversions_path,
          params: { conversion: { event_id: event.prefix_id, conversion_type: "signup", revenue: 99.99 } },
          headers: auth_headers

        assert_response :created
        assert_equal "signup", response.parsed_body.dig("conversion", "conversion_type")
      end

      test "returns pending attribution status in response" do
        post api_v1_conversions_path,
          params: { conversion: { event_id: event.prefix_id, conversion_type: "signup" } },
          headers: auth_headers

        assert_response :created
        assert response.parsed_body.key?("attribution")
        assert_equal "pending", response.parsed_body.dig("attribution", "status")
      end

      test "returns 422 with invalid event_id" do
        post api_v1_conversions_path,
          params: { conversion: { event_id: "evt_invalid", conversion_type: "signup" } },
          headers: auth_headers

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"], "Event not found"
      end

      test "prevents cross-account event access" do
        other_event = events(:three)

        post api_v1_conversions_path,
          params: { conversion: { event_id: other_event.prefix_id, conversion_type: "signup" } },
          headers: auth_headers

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"], "Event belongs to different account"
      end

      # ==========================================
      # Visitor-based conversion tests
      # ==========================================

      test "creates conversion with visitor_id" do
        post api_v1_conversions_path,
          params: { conversion: { visitor_id: visitor.visitor_id, conversion_type: "signup", revenue: 99.99 } },
          headers: auth_headers

        assert_response :created
        assert_equal "signup", response.parsed_body.dig("conversion", "conversion_type")
      end

      test "returns 422 with invalid visitor_id" do
        post api_v1_conversions_path,
          params: { conversion: { visitor_id: "invalid_visitor", conversion_type: "signup" } },
          headers: auth_headers

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"], "Visitor not found"
      end

      test "prevents cross-account visitor access" do
        other_visitor = visitors(:three)

        post api_v1_conversions_path,
          params: { conversion: { visitor_id: other_visitor.visitor_id, conversion_type: "signup" } },
          headers: auth_headers

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"], "Visitor not found"
      end

      # ==========================================
      # Identifier validation tests
      # ==========================================

      test "returns 422 when neither event_id nor visitor_id provided" do
        post api_v1_conversions_path,
          params: { conversion: { conversion_type: "signup" } },
          headers: auth_headers

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"], "event_id or visitor_id is required"
      end

      # ==========================================
      # Common validation tests
      # ==========================================

      test "returns 401 without API key" do
        post api_v1_conversions_path,
          params: { conversion: { event_id: event.prefix_id, conversion_type: "signup" } }

        assert_response :unauthorized
      end

      test "returns 422 with missing conversion_type" do
        post api_v1_conversions_path,
          params: { conversion: { event_id: event.prefix_id } },
          headers: auth_headers

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"], "conversion_type is required"
      end

      test "accepts properties parameter" do
        post api_v1_conversions_path,
          params: {
            conversion: {
              event_id: event.prefix_id,
              conversion_type: "signup",
              properties: { plan: "pro", coupon: "SAVE20" }
            }
          },
          headers: auth_headers

        assert_response :created
      end

      private

      def event
        @event ||= events(:one)
      end

      def visitor
        @visitor ||= visitors(:one)
      end

      def auth_headers
        { "Authorization" => "Bearer sk_test_abc123xyz789" }
      end
    end
  end
end
