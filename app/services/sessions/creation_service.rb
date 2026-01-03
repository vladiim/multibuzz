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

      process_visitor
      process_session

      success_result(
        visitor_id: visitor_id,
        session_id: session_id,
        channel: session.channel
      )
    end

    def process_visitor
      visitor # trigger find_or_create
      increment_usage! if visitor_created?
      visitor.update!(last_seen_at: started_at) unless visitor_created?
    end

    def process_session
      session_created?.tap { |created| increment_usage! if created }
    end

    def visitor_created?
      @visitor_created
    end

    def session_created?
      return @session_created if defined?(@session_created)

      was_new = !session.persisted?
      create_or_update_session
      @session_created = was_new
    end

    def increment_usage!
      Billing::UsageCounter.new(account).increment!
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
      canonical_visitor || find_or_create_by_visitor_id
    end

    # Detect concurrent Turbo frame requests by checking for recent sessions
    # with the same session_id. All concurrent requests generate the SAME
    # session_id (fingerprint-based) but DIFFERENT random visitor_ids.
    # Reusing the canonical visitor prevents duplicate visitor creation.
    def canonical_visitor
      return @canonical_visitor if defined?(@canonical_visitor)

      existing_session = account.sessions
        .where(session_id: session_id)
        .where("sessions.created_at > ?", 30.seconds.ago)
        .order(:created_at)
        .first

      @canonical_visitor = existing_session&.visitor
    end

    def find_or_create_by_visitor_id
      account.visitors.find_or_create_by!(visitor_id: visitor_id) do |v|
        v.first_seen_at = started_at
        v.last_seen_at = started_at
        v.is_test = is_test
        @visitor_created = true
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
      # First check if session exists for the current visitor
      existing_for_visitor = account.sessions.find_by(session_id: session_id, visitor: visitor)
      return existing_for_visitor if existing_for_visitor

      # Race condition safeguard: check if ANY session exists with this session_id
      # This catches cases where canonical_visitor was queried before first session committed
      existing_any = account.sessions
        .where(session_id: session_id)
        .where("sessions.created_at > ?", 30.seconds.ago)
        .order(:created_at)
        .first

      if existing_any && existing_any.visitor != visitor
        # Another request created a session - use their visitor for consistency
        @visitor = existing_any.visitor
        return existing_any
      end

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
        channel: channel,
        click_ids: click_ids
      }.compact
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
      @channel ||= Sessions::ChannelAttributionService.new(
        normalized_utm,
        referrer,
        click_ids,
        page_host: page_host
      ).call
    end

    def page_host
      @page_host ||= URI.parse(url).host
    rescue URI::InvalidURIError
      nil
    end
  end
end
