module Dashboard
  class FunnelController < BaseController
    def show
      @filter_params = filter_params
      @demo_mode = demo_mode?

      @result = if demo_mode?
        Dashboard::Dummy::FunnelDataService.call
      else
        Dashboard::FunnelDataService.new(current_account, filter_params).call
      end
    end
  end
end
