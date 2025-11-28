module Dashboard
  class EventsController < BaseController
    def show
      @filter_params = filter_params
      @result = Dashboard::FunnelDataService.new(current_account, filter_params).call
    end
  end
end
