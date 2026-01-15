# frozen_string_literal: true

module ApiRequestLogs
  class RecordService < ApplicationService
    SENSITIVE_KEYS = %w[password token secret key api_key authorization].freeze
    ALLOWED_PARAM_KEYS = %w[event_type visitor_id session_id conversion_type user_id].freeze
    SDK_USER_AGENT_PATTERN = /^(mbuzz-\w+)\/(\d+\.\d+\.\d+)/.freeze
    UNKNOWN_SDK = "unknown"
    IPV4_OCTET_COUNT = 4
    ANONYMIZED_LAST_OCTET = "0"
    ENDPOINT_SEGMENTS = 2

    def initialize(request:, account:, error_type:, error_message:, http_status:, error_details: {})
      @request = request
      @account = account
      @error_type = error_type
      @error_message = error_message
      @http_status = http_status
      @error_details = error_details || {}
    end

    private

    attr_reader :request, :account, :error_type, :error_message, :http_status, :error_details

    def run
      ApiRequestLog.create!(log_attributes)
      success_result
    end

    def log_attributes
      {
        account: account,
        request_id: request_id,
        endpoint: endpoint,
        http_method: http_method,
        http_status: http_status,
        error_type: error_type,
        error_message: error_message,
        error_details: error_details,
        sdk_name: sdk_name,
        sdk_version: sdk_version,
        ip_address: anonymized_ip,
        user_agent: user_agent,
        request_params: sanitized_params,
        occurred_at: Time.current
      }
    end

    def request_id
      @request_id ||= request.request_id || SecureRandom.uuid
    end

    def endpoint
      @endpoint ||= request.path.split("/").reject(&:blank?).last(ENDPOINT_SEGMENTS).join("/")
    end

    def http_method
      @http_method ||= request.method
    end

    def sdk_name
      return nil unless user_agent
      return sdk_match[1] if sdk_match

      UNKNOWN_SDK
    end

    def sdk_version
      return nil unless user_agent

      sdk_match&.[](2)
    end

    def sdk_match
      @sdk_match ||= user_agent&.match(SDK_USER_AGENT_PATTERN)
    end

    def user_agent
      @user_agent ||= request.user_agent
    end

    def anonymized_ip
      @anonymized_ip ||= anonymize_ip(remote_ip)
    end

    def remote_ip
      @remote_ip ||= request.remote_ip
    end

    def anonymize_ip(ip)
      return nil unless ip

      octets = ip.split(".")
      return ip unless octets.length == IPV4_OCTET_COUNT

      [*octets[0..2], ANONYMIZED_LAST_OCTET].join(".")
    end

    def sanitized_params
      @sanitized_params ||= raw_params.except(*SENSITIVE_KEYS).slice(*ALLOWED_PARAM_KEYS)
    end

    def raw_params
      @raw_params ||= normalize_params(request.params)
    end

    def normalize_params(params)
      return params.to_unsafe_h.deep_stringify_keys if params.respond_to?(:to_unsafe_h)

      params.to_h.deep_stringify_keys
    end
  end
end
