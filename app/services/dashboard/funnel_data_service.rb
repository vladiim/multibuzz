module Dashboard
  class FunnelDataService < ApplicationService
    def initialize(account, filter_params)
      @account = account
      @filter_params = filter_params
    end

    private

    attr_reader :account, :filter_params

    def run
      # TODO: Replace with real implementation in Phase 2
      Dummy::FunnelDataService.new.call
    end
  end
end
