module Dashboard
  class FunnelDataService < ApplicationService
    def initialize(account, filter_params)
      @account = account
      @filter_params = filter_params
    end

    private

    attr_reader :account, :filter_params

    def run
      success_result(data: { stages: stages })
    end

    def stages
      Queries::FunnelStagesQuery.new(events_scope).call
    end

    def events_scope
      @events_scope ||= Scopes::EventsScope.new(
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
