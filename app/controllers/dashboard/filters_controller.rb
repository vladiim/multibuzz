module Dashboard
  class FiltersController < BaseController
    def show
      @available_models = current_account.attribution_models.active
      @filter_params = filter_params
    end
  end
end
