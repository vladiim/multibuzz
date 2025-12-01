module Dashboard
  class ConversionsDataService < ApplicationService
    def initialize(account, filter_params)
      @account = account
      @filter_params = filter_params
    end

    private

    attr_reader :account, :filter_params

    def run
      success_result(data: {
        totals: totals,
        by_channel: by_channel,
        time_series: time_series,
        top_campaigns: top_campaigns
      })
    end

    def totals
      Queries::TotalsQuery.new(credits_scope, prior_scope: prior_credits_scope).call
    end

    def by_channel
      Queries::ByChannelQuery.new(credits_scope).call
    end

    def time_series
      Queries::TimeSeriesQuery.new(credits_scope, date_range: date_range).call
    end

    def top_campaigns
      Queries::TopCampaignsQuery.new(credits_scope).call
    end

    def credits_scope
      @credits_scope ||= build_scope(date_range)
    end

    def prior_credits_scope
      @prior_credits_scope ||= build_scope(date_range.prior_period)
    end

    def build_scope(range)
      Scopes::CreditsScope.new(
        account: account,
        models: filter_params[:models],
        date_range: range,
        channels: filter_params[:channels]
      ).call
    end

    def date_range
      @date_range ||= DateRangeParser.new(filter_params[:date_range])
    end
  end
end
