class DashboardController < Dashboard::BaseController
  def show
    @account = current_account
    @live_events = load_live_events
    @test_only = test_mode?
  end

  private

  def load_live_events
    scoped_events
      .includes(:session, :visitor)
      .order(occurred_at: :desc)
      .limit(100)
  end
end
