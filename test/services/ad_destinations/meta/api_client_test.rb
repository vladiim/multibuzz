# frozen_string_literal: true

require "test_helper"

module AdDestinations
  module Meta
    class ApiClientTest < ActiveSupport::TestCase
      setup do
        Rails.cache.clear
      end

      test "POSTs payload to graph.facebook.com/{API_VERSION}/{pixel_id}/events" do
        expected_url = "#{Platforms::Meta::Capi::GRAPH_HOST}/#{Platforms::Meta::Capi::API_VERSION}/123_PIXEL/events"
        stub = stub_request(:post, expected_url).with(query: { "access_token" => "TOKEN_X" })
          .to_return(status: 200, body: { events_received: 1 }.to_json, headers: { "Content-Type" => "application/json" })

        ApiClient.new(destination(meta_pixel_id: "123_PIXEL", meta_access_token: "TOKEN_X")).post({ data: [] })

        assert_requested stub
      end

      test "returns success result for 200 response" do
        stub_meta_response(status: 200, body: { events_received: 1, fbtrace_id: "AbCd" })
        result = ApiClient.new(destination).post({ data: [] })

        assert_predicate result, :success?
        assert_equal 200, result.http_status
        assert_equal 1, result.body["events_received"]
      end

      test "returns auth_failure? for 401" do
        stub_meta_response(status: 401, body: { error: { type: "OAuthException", message: "Invalid token" } })
        result = ApiClient.new(destination).post({ data: [] })

        assert_predicate result, :auth_failure?
        refute_predicate result, :success?
      end

      test "returns transient_failure? for 429" do
        stub_meta_response(status: 429, body: { error: { message: "Rate limit hit" } })
        result = ApiClient.new(destination).post({ data: [] })

        assert_predicate result, :transient_failure?
        assert_predicate result, :rate_limited?
      end

      test "returns transient_failure? for 5xx" do
        stub_meta_response(status: 503, body: { error: { message: "Service unavailable" } })
        result = ApiClient.new(destination).post({ data: [] })

        assert_predicate result, :transient_failure?
        refute_predicate result, :rate_limited?
      end

      test "returns permanent_failure? for 400 (bad payload)" do
        stub_meta_response(status: 400, body: { error: { message: "Invalid event_name" } })
        result = ApiClient.new(destination).post({ data: [] })

        assert_predicate result, :permanent_failure?
        refute_predicate result, :transient_failure?
        refute_predicate result, :auth_failure?
      end

      test "increments meta_capi usage tracker on every call" do
        stub_meta_response(status: 200, body: {})

        assert_difference -> { AdPlatforms::ApiUsageTracker.current_usage(:meta_capi) } do
          ApiClient.new(destination).post({ data: [] })
        end
      end

      test "increments meta_capi usage tracker even on error responses" do
        stub_meta_response(status: 500, body: { error: { message: "Boom" } })

        assert_difference -> { AdPlatforms::ApiUsageTracker.current_usage(:meta_capi) } do
          ApiClient.new(destination).post({ data: [] })
        end
      end

      private

      def destination(meta_pixel_id: "999_PIXEL", meta_access_token: "default_token")
        ConversionDestination.new(
          account: accounts(:one),
          attribution_model: attribution_models(:last_touch),
          platform: "meta_capi",
          name: "Test",
          meta_pixel_id: meta_pixel_id,
          meta_access_token: meta_access_token
        )
      end

      def stub_meta_response(status:, body:)
        stub_request(:post, %r{#{Regexp.escape(Platforms::Meta::Capi::GRAPH_HOST)}/.+/events})
          .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
      end
    end
  end
end
