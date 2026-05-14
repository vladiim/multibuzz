# frozen_string_literal: true

# Wrapper around a Meta CAPI HTTP response. Lets the dispatcher decide
# the next step (deliver / retry / fail / refresh-token) without
# inspecting raw status codes or response bodies.
#
# Status code groupings follow Meta's CAPI conventions:
# - 2xx: success
# - 401, 403: auth failure (token expired or revoked) - refresh & retry once
# - 429: rate limit - retry with backoff
# - 5xx: transient failure - retry with backoff
# - 4xx (other): permanent failure - capture, surface, no retry
module AdDestinations
  module Meta
    class Result
      SUCCESS_RANGE = (200..299).freeze
      AUTH_FAILURE_STATUSES = [ 401, 403 ].freeze
      RATE_LIMIT_STATUS = 429
      TRANSIENT_FAILURE_RANGE = (500..599).freeze

      def initialize(http_status:, body:)
        @http_status = http_status
        @body = body
      end

      attr_reader :http_status, :body

      def success?
        SUCCESS_RANGE.cover?(http_status)
      end

      def auth_failure?
        AUTH_FAILURE_STATUSES.include?(http_status)
      end

      def rate_limited?
        http_status == RATE_LIMIT_STATUS
      end

      def transient_failure?
        rate_limited? || TRANSIENT_FAILURE_RANGE.cover?(http_status)
      end

      def permanent_failure?
        return false if success? || auth_failure? || transient_failure?

        true
      end

      def error_message
        body.dig("error", "message")
      end
    end
  end
end
