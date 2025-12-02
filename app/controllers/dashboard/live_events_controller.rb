module Dashboard
  class LiveEventsController < BaseController
    def show
      @events = recent_events
      @test_only = test_only?
    end

    private

    def recent_events
      scope = current_account.events.includes(:session)
      scope = scope.where(is_test: true) if test_only?
      scope.order(occurred_at: :desc).limit(100)
    end

    def test_only?
      params[:test_only] == "true"
    end
  end
end
