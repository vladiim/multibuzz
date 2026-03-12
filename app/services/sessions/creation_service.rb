# frozen_string_literal: true

module Sessions
  class CreationService < ApplicationService
    def initialize(account, params, is_test: false)
      @account = account
      @params = params
      @is_test = is_test
    end

    private

    attr_reader :account, :params, :is_test

    def request_id
      params[:request_id]
    end

    def device_fingerprint
      params[:device_fingerprint]
    end

    def existing_by_request_id
      return nil unless request_id.present?

      @existing_session = account.sessions.find_by(request_id: request_id)
    end

    def idempotent_result
      success_result(
        visitor_id: @existing_session.visitor.visitor_id,
        session_id: @existing_session.session_id,
        channel: @existing_session.channel
      )
    end

    def store_request_id
      return unless request_id.present?

      session.update_column(:request_id, request_id)
    end

    def run
      return validation_error if validation_error
      return idempotent_result if existing_by_request_id

      with_session_lock do
        process_visitor
        process_session
      end

      store_request_id

      success_result(
        visitor_id: visitor_id,
        session_id: session_id,
        channel: session.channel
      )
    end

    def validation_error
      return error_result([ "visitor_id is required" ]) unless visitor_id.present?
      return error_result([ "session_id is required" ]) unless session_id.present?
      error_result([ "url is required" ]) unless url.present?
    end

    def with_session_lock
      lock_value = device_fingerprint.presence || session_id
      lock_key = Digest::MD5.hexdigest("#{account.id}:#{lock_value}").to_i(16) % (2**31)
      ActiveRecord::Base.transaction do
        ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{lock_key})")
        yield
      end
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

    def canonical_visitor
      return @canonical_visitor if defined?(@canonical_visitor)

      @canonical_visitor = find_canonical_by_fingerprint || find_canonical_by_session_id
    end

    def find_canonical_by_fingerprint
      return unless device_fingerprint.present?

      recent_fingerprint_session&.visitor
    end

    def recent_fingerprint_session
      account.sessions
        .where(device_fingerprint: device_fingerprint)
        .where("sessions.created_at > ?", 30.seconds.ago)
        .order(:created_at)
        .first
    end

    def find_canonical_by_session_id
      recent_session_with_same_id&.visitor
    end

    def find_or_create_by_visitor_id
      check_for_concurrent_session
      return @canonical_visitor if @canonical_visitor

      account.visitors.find_or_create_by!(visitor_id: visitor_id) do |v|
        v.first_seen_at = started_at
        v.last_seen_at = started_at
        v.is_test = is_test
        @visitor_created = true
      end
    end

    def check_for_concurrent_session
      return if defined?(@canonical_visitor)

      existing = recent_fingerprint_session || recent_session_with_same_id
      @canonical_visitor = existing&.visitor
    end

    def recent_session_with_same_id
      account.sessions
        .where(session_id: session_id)
        .where("sessions.created_at > ?", 30.seconds.ago)
        .order(:created_at)
        .first
    end

    def create_or_update_session
      return update_activity! if session_reused?
      return if session.persisted? && session.initial_utm.present?

      session.assign_attributes(session_attributes)
      session.save!
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      handle_session_race_condition
    end

    def session_reused?
      active_visitor_session.present? && session.id == active_visitor_session.id
    end

    def update_activity!
      session.update!(last_activity_at: started_at)
    end

    def handle_session_race_condition
      orphaned_visitor = @visitor if @visitor_created
      @session = account.sessions.find_by!(session_id: session_id)
      @visitor = session.visitor
      @session_created = false
      @visitor_created = false
      delete_orphaned_visitor(orphaned_visitor)
    end

    def delete_orphaned_visitor(orphaned_visitor)
      return unless orphaned_visitor
      return if orphaned_visitor == @visitor

      orphaned_visitor.destroy
    end

    def session
      @session ||= find_or_initialize_session
    end

    def find_or_initialize_session
      existing_for_visitor = account.sessions.find_by(session_id: session_id, visitor: visitor)
      return existing_for_visitor if existing_for_visitor

      existing_any = recent_session_with_same_id
      return adopt_existing_session(existing_any) if existing_any

      return active_visitor_session if reuse_active_session?

      account.sessions.new(
        session_id: session_id,
        visitor: visitor,
        device_fingerprint: device_fingerprint,
        started_at: started_at,
        last_activity_at: started_at,
        is_test: is_test
      )
    end

    def adopt_existing_session(existing_session)
      return existing_session if existing_session.visitor == visitor

      orphaned_visitor = @visitor if @visitor_created
      @visitor = existing_session.visitor
      @visitor_created = false
      delete_orphaned_visitor(orphaned_visitor)
      existing_session
    end

    def session_attributes
      {
        initial_utm: normalized_utm,
        initial_referrer: referrer,
        channel: channel,
        click_ids: click_ids,
        suspect: classification[:suspect],
        suspect_reason: classification[:suspect_reason],
        user_agent: user_agent,
        landing_page_host: normalized_page_host
      }.compact
    end

    def classification
      @classification ||= BotClassifier.new(
        user_agent: user_agent,
        referrer: referrer,
        utm: normalized_utm,
        click_ids: click_ids
      ).call
    end

    def user_agent
      params[:user_agent]
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
        page_host: page_host,
        account_domains: account_domains
      ).call
    end

    def page_host
      @page_host ||= URI.parse(url).host || host_from_referrer
    rescue URI::InvalidURIError
      host_from_referrer
    end

    def normalized_page_host
      @normalized_page_host ||= normalize_host(page_host) if page_host.present?
    end

    def account_domains
      @account_domains ||= account.sessions
        .where.not(landing_page_host: nil)
        .distinct
        .pluck(:landing_page_host)
    end

    def host_from_referrer
      return nil unless referrer.present?

      ref_url = referrer.include?("://") ? referrer : "https://#{referrer}"
      URI.parse(ref_url).host
    rescue URI::InvalidURIError
      nil
    end

    def reuse_active_session?
      active_visitor_session.present? && !new_traffic_source?
    end

    def active_visitor_session
      @active_visitor_session ||= find_active_visitor_session
    end

    def find_active_visitor_session
      scope = account.sessions
        .where(visitor_id: visitor.id)
        .where(ended_at: nil)
        .where("last_activity_at > ?", 30.minutes.ago)
        .order(last_activity_at: :desc)

      return scope.first unless device_fingerprint.present?

      # Prefer fingerprint match, fall back to visitor_id only
      scope.where(device_fingerprint: device_fingerprint).first || scope.first
    end

    def new_traffic_source?
      normalized_utm.values.any?(&:present?) || click_ids.any? || external_referrer?
    end

    def external_referrer?
      return false unless referrer.present?

      referrer_host = URI.parse(referrer).host
      return false unless referrer_host.present?
      return false unless page_host.present?

      normalize_host(referrer_host) != normalize_host(page_host)
    rescue URI::InvalidURIError
      false
    end

    def normalize_host(host)
      host.to_s.downcase.sub(/^www\./, "").sub(/:\d+$/, "")
    end
  end
end
