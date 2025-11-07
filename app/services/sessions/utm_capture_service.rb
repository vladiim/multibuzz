module Sessions
  class UtmCaptureService
    UTM_PARAMS = %w[utm_source utm_medium utm_campaign utm_content utm_term].freeze

    def initialize
      # No dependencies needed
    end

    def call(properties)
      return {} if properties.blank?

      extract_utm_params(properties)
    end

    private

    def extract_utm_params(properties)
      UTM_PARAMS
        .each_with_object({}) { |param, result| add_utm_param(param, properties, result) }
        .compact
    end

    def add_utm_param(param, properties, result)
      value = properties[param] || properties[param.to_sym]
      result[param.to_sym] = value if value.present?
    end
  end
end
