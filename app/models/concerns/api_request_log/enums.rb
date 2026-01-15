# frozen_string_literal: true

module ApiRequestLog::Enums
  extend ActiveSupport::Concern

  included do
    enum :error_type, {
      # Auth errors (401)
      auth_missing_header: 0,
      auth_malformed_header: 1,
      auth_invalid_key: 2,
      auth_revoked_key: 3,
      auth_account_suspended: 4,

      # Validation errors (400)
      validation_missing_param: 10,
      validation_invalid_format: 11,
      validation_invalid_type: 12,

      # Business logic errors (422)
      visitor_not_found: 20,
      event_not_found: 21,
      conversion_type_missing: 22,
      rate_limit_exceeded: 23,
      billing_blocked: 24,

      # Server errors (500)
      internal_error: 90,
      database_error: 91,
      timeout_error: 92
    }
  end
end
