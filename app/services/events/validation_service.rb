module Events
  class ValidationService < ApplicationService
    def initialize(event_data)
      @event_data = event_data
    end

    private

    attr_reader :event_data

    def run
      errors = []
      errors.concat(validate_event_type)
      errors.concat(validate_identity)
      errors.concat(validate_timestamp)
      errors.concat(validate_properties)
      errors.concat(validate_funnel)

      return error_result(errors) if errors.any?

      { valid: true, errors: [] }
    end

    def validate_event_type
      return [] if field_present?("event_type")

      ["event_type is required"]
    end

    def validate_identity
      return [] if field_present?("visitor_id") || field_present?("user_id")

      ["visitor_id or user_id is required"]
    end

    def field_present?(field)
      return false unless has_field?(field)

      value = field_value(field)
      value.is_a?(Hash) || value.present?
    end

    def has_field?(field)
      event_data&.key?(field) || event_data&.key?(field.to_sym)
    end

    def validate_timestamp
      return [] unless has_field?("timestamp")

      Time.iso8601(field_value("timestamp"))
      []
    rescue ArgumentError
      ["timestamp must be a valid ISO8601 datetime"]
    end

    def validate_properties
      return [] unless has_field?("properties")
      return [] if field_value("properties").is_a?(Hash)

      ["properties must be a hash"]
    end

    def validate_funnel
      return [] unless has_field?("funnel")

      funnel = field_value("funnel")
      return [] if funnel.nil?
      return ["funnel must be a string"] unless funnel.is_a?(String)
      return ["funnel must be 255 characters or less"] if funnel.length > 255
      return ["funnel must contain only alphanumeric characters and underscores"] unless funnel.match?(/\A[a-zA-Z0-9_]+\z/)

      []
    end

    def field_value(field)
      event_data[field] || event_data[field.to_sym]
    end
  end
end
