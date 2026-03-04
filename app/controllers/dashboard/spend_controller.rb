# frozen_string_literal: true

module Dashboard
  class SpendController < BaseController
    def show
      @filter_params = filter_params
      @has_connections = current_account.ad_platform_connections.active_connections.exists?

      @result = @has_connections ? spend_result : empty_result
    end

    private

    def spend_result
      SpendIntelligence::MetricsService.new(current_account, filter_params).call
    end

    def empty_result
      { success: true, data: nil }
    end
  end
end
