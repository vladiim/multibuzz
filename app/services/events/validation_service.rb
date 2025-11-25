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

      return error_result(errors) if errors.any?

      { valid: true, errors: [] }
    end

    def validate_required_fields
      REQUIRED_FIELDS.map do |field|
        "#{field} is required" unless event_data&.key?(field)
      end.compact
    end

    def validate_timestamp
      return [] unless event_data&.key?("timestamp")

      Time.iso8601(event_data["timestamp"])
      []
    rescue ArgumentError
      ["timestamp must be a valid ISO8601 datetime"]
    end

    def validate_properties
      return [] unless event_data&.key?("properties")
      return [] if event_data["properties"].is_a?(Hash)

      ["properties must be a hash"]
    end
  end
end
