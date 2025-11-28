module Dashboard
  class ConversionsController < BaseController
    def show
      @filter_params = filter_params
      @result = Dashboard::ConversionsDataService.new(current_account, filter_params).call
    end
  end
end
