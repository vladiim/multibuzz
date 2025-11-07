module Events
  class ValidationService
    REQUIRED_FIELDS = %w[event_type visitor_id session_id timestamp properties].freeze

    def initialize
      # No dependencies needed
    end

    def call(event_data)
      errors = []
      errors.concat(validate_required_fields(event_data))
      errors.concat(validate_timestamp(event_data))
      errors.concat(validate_properties(event_data))

      { valid: errors.empty?, errors: errors }
    end

    private

    def validate_required_fields(event_data)
      REQUIRED_FIELDS.map do |field|
        "#{field} is required" unless event_data&.key?(field)
      end.compact
    end

    def validate_timestamp(event_data)
      return [] unless event_data&.key?("timestamp")

      Time.iso8601(event_data["timestamp"])
      []
    rescue ArgumentError
      ["timestamp must be a valid ISO8601 datetime"]
    end

    def validate_properties(event_data)
      return [] unless event_data&.key?("properties")
      return [] if event_data["properties"].is_a?(Hash)

      ["properties must be a hash"]
    end
  end
end
