module Events
  class ProcessingService
    def initialize(account, event_data)
      @account = account
      @event_data = event_data
    end

    def call
      return error_result(visitor_result[:errors]) unless visitor_result[:success]
      return error_result(session_result[:errors]) unless session_result[:success]

      capture_utm_if_new_session
      save_event
    end

    private

    attr_reader :account, :event_data

    def visitor_result
      @visitor_result ||= Visitors::LookupService.new(account).call(event_data["visitor_id"])
    end

    def session_result
      @session_result ||= Sessions::TrackingService.new(account).call(event_data["session_id"], visitor)
    end

    def visitor
      visitor_result[:visitor]
    end

    def session
      session_result[:session]
    end

    def url
      event_data["url"] || event_data[:url]
    end

    def referrer
      event_data["referrer"] || event_data[:referrer]
    end

    def utm_data
      @utm_data ||= Sessions::UtmCaptureService.new(url).call(event_properties)
    end

    def event_properties
      event_data["properties"] || event_data[:properties]
    end

    def channel
      @channel ||= Sessions::ChannelAttributionService.new(utm_data, referrer).call
    end

    def capture_utm_if_new_session
      return unless session.initial_utm.blank?

      session.update(
        initial_utm: utm_data,
        initial_referrer: referrer,
        channel: channel
      )
    end

    def save_event
      return success_result(event) if event.save

      error_result(event.errors.full_messages)
    end

    def event
      @event ||= build_event
    end

    def build_event
      account.events.build(
        event_type: event_data["event_type"],
        visitor: visitor,
        session: session,
        occurred_at: Time.iso8601(event_data["timestamp"]),
        properties: event_data["properties"]
      )
    end

    def success_result(event)
      { success: true, event: event }
    end

    def error_result(errors)
      { success: false, errors: errors }
    end
  end
end
