module Sessions
  class UtmCaptureService
    UTM_PARAMS = %w[utm_source utm_medium utm_campaign utm_content utm_term].freeze

    def initialize(url = nil)
      @url = url
    end

    def call(properties = nil)
      return extract_from_url if url.present?
      return {} if properties.blank?

      extract_from_properties(properties)
    end

    private

    attr_reader :url

    def extract_from_url
      return {} unless parsed_uri

      query_params = URI.decode_www_form(parsed_uri.query || "").to_h
      extract_from_properties(query_params)
    end

    def parsed_uri
      @parsed_uri ||= URI.parse(url)
    rescue URI::InvalidURIError
      nil
    end

    def extract_from_properties(properties)
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
