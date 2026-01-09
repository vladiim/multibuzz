module Events
  class ProcessingService < ApplicationService
    def initialize(account, event_data, is_test: false)
      @account = account
      @event_data = event_data
      @is_test = is_test
    end

    private

    attr_reader :account, :event_data, :is_test

    def run
      return error_result(visitor_result[:errors]) unless visitor_result[:success]
      return error_result(session_result[:errors]) unless session_result[:success]

      capture_utm_if_new_session
      save_event
    end

    def visitor_result
      @visitor_result ||= Visitors::LookupService.new(account, event_data["visitor_id"], is_test: is_test).call
    end

    def session_result
      @session_result ||= Sessions::TrackingService.new(
        account,
        resolved_session_id,
        visitor,
        event_timestamp: event_timestamp,
        is_test: is_test,
        device_fingerprint: device_fingerprint
      ).call
    end

    def resolved_session_id
      @resolved_session_id ||= server_side_resolution? ? resolve_session_server_side : client_session_id
    end

    def server_side_resolution?
      event_ip.present? && event_user_agent.present?
    end

    def resolve_session_server_side
      Sessions::ResolutionService.new(
        account: account,
        visitor_id: event_visitor_id,
        ip: event_ip,
        user_agent: event_user_agent,
        identifier: event_identifier
      ).call
    end

    def event_visitor_id
      event_data["visitor_id"] || event_data[:visitor_id]
    end

    def client_session_id
      event_data["session_id"]
    end

    def event_ip
      event_data["ip"] || event_data[:ip]
    end

    def event_user_agent
      event_data["user_agent"] || event_data[:user_agent]
    end

    def event_identifier
      event_data["identifier"] || event_data[:identifier]
    end

    def device_fingerprint
      return nil unless server_side_resolution?

      @device_fingerprint ||= Digest::SHA256.hexdigest("#{event_ip}|#{event_user_agent}")[0, 32]
    end

    def event_timestamp
      @event_timestamp ||= Time.iso8601(event_data["timestamp"])
    end

    def visitor
      visitor_result[:visitor]
    end

    def session
      session_result[:session]
    end

    def url
      event_data["url"] || event_data[:url] || event_properties&.dig("url") || event_properties&.dig(:url)
    end

    def referrer
      event_data["referrer"] || event_data[:referrer] || event_properties&.dig("referrer") || event_properties&.dig(:referrer)
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
      return success_result(event: event) if event.save

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
        occurred_at: event_timestamp,
        properties: event_data["properties"],
        funnel: event_data["funnel"] || event_data[:funnel],
        is_test: is_test,
        locked: should_lock_event?
      )
    end

    def should_lock_event?
      account.should_lock_events?
    end
  end
end
