# frozen_string_literal: true

module Api
  module Internal
    # POST /api/internal/consent — records a marketing analytics consent
    # decision from the cookie banner. Anonymous endpoint: no API key
    # required, no account scoping. Writes a ConsentLog row with the
    # hashed IP, country, banner version, and consent payload.
    class ConsentController < BaseController
      USER_AGENT_HEADER = "User-Agent"
      IP_HASH_BYTE_LENGTH = 32

      rate_limit to: 20, within: 1.minute,
        by: -> { real_client_ip },
        with: -> { head :too_many_requests }

      def create
        consent_log.save!
        head :created
      rescue ActiveRecord::RecordInvalid
        head :unprocessable_content
      end

      private

      def consent_log
        @consent_log ||= ConsentLog.new(
          consent_payload: payload_param,
          banner_version: banner_version_param,
          visitor_id: visitor_id_param,
          ip_hash: hashed_ip,
          country: visitor_country(request),
          region: visitor_region(request),
          user_agent: request.headers[USER_AGENT_HEADER]
        )
      end

      def payload_param
        params[:payload]
      end

      def banner_version_param
        params[:banner_version]
      end

      def visitor_id_param
        params[:visitor_id]
      end

      def hashed_ip
        Digest::SHA256.hexdigest(real_client_ip.to_s)
      end
    end
  end
end
