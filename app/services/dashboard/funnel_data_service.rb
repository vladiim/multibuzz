# frozen_string_literal: true

module Dashboard
  class FunnelDataService < ApplicationService
    CACHE_TTL = 5.minutes

    def initialize(account, filter_params)
      @account = account
      @filter_params = filter_params
    end

    private

    attr_reader :account, :filter_params

    def run
      success_result(data: cached_data.merge(available_funnels: available_funnels))
    end

    def cached_data
      Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { query_data }
    end

    def query_data
      { stages: stages }
    end

    def available_funnels
      @available_funnels ||= account.events
        .where.not(funnel: nil)
        .distinct
        .pluck(:funnel)
        .sort
    end

    def cache_key
      "dashboard/funnel/#{account.prefix_id}/#{params_hash}"
    end

    def params_hash
      Digest::MD5.hexdigest(cache_params.to_json)[0..11]
    end

    def cache_params
      {
        date_range: filter_params[:date_range],
        channels: filter_params[:channels].sort,
        unique_users: unique_users,
        funnel: funnel
      }
    end

    def funnel
      filter_params[:funnel]
    end

    def stages
      Queries::FunnelStagesQuery.new(
        events_scope,
        sessions_scope: sessions_scope,
        conversions_scope: conversions_scope,
        unique_users: unique_users
      ).call
    end

    def unique_users
      filter_params.fetch(:unique_users, true)
    end

    def events_scope
      @events_scope ||= Scopes::EventsScope.new(
        account: account,
        date_range: date_range,
        channels: filter_params[:channels],
        funnel: funnel
      ).call
    end

    def sessions_scope
      @sessions_scope ||= Scopes::SessionsScope.new(
        account: account,
        date_range: date_range,
        channels: filter_params[:channels]
      ).call
    end

    def conversions_scope
      @conversions_scope ||= Scopes::ConversionsScope.new(
        account: account,
        date_range: date_range,
        channels: filter_params[:channels]
      ).call
    end

    def date_range
      @date_range ||= DateRangeParser.new(filter_params[:date_range])
    end
  end
end
