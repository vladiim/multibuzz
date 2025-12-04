module Events
  class ValidationService < ApplicationService
    REQUIRED_FIELDS = %w[event_type visitor_id session_id timestamp properties].freeze

    def initialize(event_data)
      @event_data = event_data
    end

    private

    attr_reader :event_data

    def run
      errors = []
      errors.concat(validate_required_fields)
      errors.concat(validate_timestamp)
      errors.concat(validate_properties)
      errors.concat(validate_funnel)

      return error_result(errors) if errors.any?

      { valid: true, errors: [] }
    end

    def validate_required_fields
      REQUIRED_FIELDS.map do |field|
        "#{field} is required" unless field_present?(field)
      end.compact
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
