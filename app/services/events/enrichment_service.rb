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
        properties: base_properties.merge(request_metadata)
      }
    end

    def base_properties
      event_data[:properties] || event_data["properties"] || {}
    end

    def request_metadata
      {
        request_metadata: {
          ip_address: anonymized_ip,
          user_agent: user_agent,
          language: accept_language,
          dnt: do_not_track
        }
      }
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
