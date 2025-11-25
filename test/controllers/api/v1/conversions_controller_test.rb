# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class ConversionsControllerTest < ActionDispatch::IntegrationTest
      test "creates conversion with valid params" do
        post api_v1_conversions_path,
          params: conversion_params,
          headers: auth_headers

        assert_response :created
        assert_equal "signup", response.parsed_body.dig("conversion", "conversion_type")
      end

      test "returns attribution credits in response" do
        post api_v1_conversions_path,
          params: conversion_params,
          headers: auth_headers

        assert_response :created
        assert response.parsed_body.key?("attribution")
        assert response.parsed_body.dig("attribution", "models").present?
      end

      test "returns 401 without API key" do
        post api_v1_conversions_path,
          params: conversion_params

        assert_response :unauthorized
      end

      test "returns 422 with missing event_id" do
        post api_v1_conversions_path,
          params: { conversion: { conversion_type: "signup" } },
          headers: auth_headers

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"], "event_id is required"
      end

      test "returns 422 with missing conversion_type" do
        post api_v1_conversions_path,
          params: { conversion: { event_id: event.prefix_id } },
          headers: auth_headers

        assert_response :unprocessable_entity
        assert_includes response.parsed_body["errors"], "conversion_type is required"
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

      private

      def conversion_params
        {
          conversion: {
            event_id: event.prefix_id,
            conversion_type: "signup",
            revenue: 99.99
          }
        }
      end

      def event
        @event ||= events(:one)
      end

      def auth_headers
        { "Authorization" => "Bearer sk_test_abc123xyz789" }
      end
    end
  end
end
