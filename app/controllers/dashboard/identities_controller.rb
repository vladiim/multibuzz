# frozen_string_literal: true

module Dashboard
  class IdentitiesController < BaseController
    skip_marketing_analytics

    def show
      @identity = identity_query.call(params[:id])
      return head(:not_found) unless @identity

      @engagement_score = EngagementScoreCalculator.new(current_account, @identity).call
    end

    private

    def identity_query
      @identity_query ||= IdentityDetailQuery.new(current_account)
    end
  end
end
