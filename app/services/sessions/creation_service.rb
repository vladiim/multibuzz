module Sessions
  class CreationService < ApplicationService
    def initialize(account, params, is_test: false)
      @account = account
      @params = params
      @is_test = is_test
    end

    private

    attr_reader :account, :params, :is_test

    def run
      return error_result(["visitor_id is required"]) unless visitor_id.present?
      return error_result(["session_id is required"]) unless session_id.present?
      return error_result(["url is required"]) unless url.present?

      create_or_update_visitor
      create_or_update_session

      success_result(
        visitor_id: visitor_id,
        session_id: session_id,
        channel: session.channel
      )
    end

    def visitor_id
      params[:visitor_id]
    end

    def session_id
      params[:session_id]
    end

    def url
      params[:url]
    end

    def referrer
      params[:referrer]
    end

    def started_at
      @started_at ||= parse_timestamp(params[:started_at]) || Time.current
    end

    def parse_timestamp(value)
      return nil unless value.present?

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end

    def create_or_update_visitor
      visitor.update!(last_seen_at: started_at) if visitor.persisted?
    end

    def visitor
      @visitor ||= find_or_create_visitor
    end

    def find_or_create_visitor
      account.visitors.find_or_create_by!(visitor_id: visitor_id) do |v|
        v.first_seen_at = started_at
        v.last_seen_at = started_at
        v.is_test = is_test
      end
    end

    def create_or_update_session
      return if session.persisted? && session.initial_utm.present?

      session.assign_attributes(session_attributes)
      session.save!
    end

    def session
      @session ||= find_or_initialize_session
    end

    def find_or_initialize_session
      existing = account.sessions.find_by(session_id: session_id, visitor: visitor)
      return existing if existing

      account.sessions.new(
        session_id: session_id,
        visitor: visitor,
        started_at: started_at,
        is_test: is_test
      )
    end

    def session_attributes
      {
        initial_utm: normalized_utm,
        initial_referrer: referrer,
        channel: channel
      }.merge(click_ids).compact
    end

    def raw_utm_data
      @raw_utm_data ||= Sessions::UtmCaptureService.new(url).call
    end

    def normalized_utm
      @normalized_utm ||= Sessions::UtmNormalizationService.new(raw_utm_data).call
    end

    def click_ids
      @click_ids ||= Sessions::ClickIdCaptureService.new(url: url).call
    end

    def channel
      @channel ||= Sessions::ChannelAttributionService.new(normalized_utm, referrer, click_ids).call
    end
  end
end
