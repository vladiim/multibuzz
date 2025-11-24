module Events
  class EnrichmentService
    def initialize(request, event_data)
      @request = request
      @event_data = event_data
    end

    def call
      event_data.merge(enriched_properties)
    end

    private

    attr_reader :request, :event_data

    def enriched_properties
      {
        properties: base_properties
          .merge(request_metadata)
          .merge(url_components)
          .merge(referrer_components)
          .merge(utm_parameters)
      }
    end

    def base_properties
      event_data[:properties] || event_data["properties"] || {}
    end

    def request_metadata
      {
        PropertyKeys::REQUEST_METADATA.to_sym => {
          ip_address: anonymized_ip,
          user_agent: user_agent,
          language: accept_language,
          dnt: do_not_track
        }
      }
    end

    def url_components
      return {} unless url_string.present?
      return { PropertyKeys::QUERY_PARAMS.to_sym => {} } unless valid_parsed_url?

      {
        PropertyKeys::HOST.to_sym => parsed_url.host,
        PropertyKeys::PATH.to_sym => parsed_url.path.presence || "/",
        PropertyKeys::QUERY_PARAMS.to_sym => parse_query_params(parsed_url.query)
      }.compact
    end

    def valid_parsed_url?
      parsed_url.present? && parsed_url.host.present?
    end

    def referrer_components
      return {} unless referrer_string.present?
      return {} unless valid_parsed_referrer?

      {
        PropertyKeys::REFERRER_HOST.to_sym => parsed_referrer.host,
        PropertyKeys::REFERRER_PATH.to_sym => parsed_referrer.path.presence
      }.compact
    end

    def valid_parsed_referrer?
      parsed_referrer.present? && parsed_referrer.host.present?
    end

    def utm_parameters
      return {} unless parsed_query_params.present?

      {
        PropertyKeys::UTM_SOURCE.to_sym => existing_utm_value(UtmKeys::SOURCE),
        PropertyKeys::UTM_MEDIUM.to_sym => existing_utm_value(UtmKeys::MEDIUM),
        PropertyKeys::UTM_CAMPAIGN.to_sym => existing_utm_value(UtmKeys::CAMPAIGN),
        PropertyKeys::UTM_CONTENT.to_sym => existing_utm_value(UtmKeys::CONTENT),
        PropertyKeys::UTM_TERM.to_sym => existing_utm_value(UtmKeys::TERM)
      }.compact
    end

    def existing_utm_value(utm_key)
      base_properties[utm_key.to_sym] || base_properties[utm_key] || parsed_query_params[utm_key]
    end

    def parse_query_params(query_string)
      return {} if query_string.blank?

      URI.decode_www_form(query_string).to_h
    rescue => e
      {}
    end

    def parsed_query_params
      @parsed_query_params ||= begin
        return {} unless url_string.present?

        parse_query_params(parsed_url&.query)
      rescue URI::InvalidURIError
        {}
      end
    end

    def parsed_url
      @parsed_url ||= URI.parse(url_string) if url_string.present?
    rescue URI::InvalidURIError
      nil
    end

    def parsed_referrer
      @parsed_referrer ||= URI.parse(referrer_string) if referrer_string.present?
    rescue URI::InvalidURIError
      nil
    end

    def url_string
      base_properties[PropertyKeys::URL.to_sym] || base_properties[PropertyKeys::URL]
    end

    def referrer_string
      base_properties[PropertyKeys::REFERRER.to_sym] || base_properties[PropertyKeys::REFERRER]
    end

    def anonymized_ip
      @anonymized_ip ||= IPAddr.new(request.ip).mask(24).to_s
    rescue IPAddr::Error
      nil
    end

    def user_agent
      request.user_agent
    end

    def accept_language
      request.headers["Accept-Language"]
    end

    def do_not_track
      request.headers["DNT"]
    end
  end
end
