# frozen_string_literal: true

require "httparty"
require_relative "test_config"

module VerificationHelper
  class << self
    # Verify test data via the verification endpoint
    # Returns hash with :visitor, :sessions, :events, :identity, :conversions
    def verify(visitor_id:, user_id: nil)
      response = HTTParty.get(
        TestConfig.verification_endpoint,
        query: { visitor_id: visitor_id, user_id: user_id }.compact,
        headers: auth_headers
      )

      return nil unless response.success?

      symbolize_keys(response.parsed_response)
    end

    # Cleanup test data after each test
    def cleanup(visitor_id:)
      HTTParty.delete(
        TestConfig.verification_endpoint,
        query: { visitor_id: visitor_id },
        headers: auth_headers
      )
    end

    private

    def auth_headers
      {
        "Authorization" => "Bearer #{TestConfig.api_key}",
        "Content-Type" => "application/json"
      }
    end

    def symbolize_keys(obj)
      case obj
      when Hash
        obj.transform_keys(&:to_sym).transform_values { |v| symbolize_keys(v) }
      when Array
        obj.map { |v| symbolize_keys(v) }
      else
        obj
      end
    end
  end
end
