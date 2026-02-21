# frozen_string_literal: true

class DashboardController < Dashboard::BaseController
  def show
    @account = current_account
    @feed_items = load_feed_items
    @test_only = test_mode?
  end

  private

  def load_feed_items
    UnifiedFeed::QueryService
      .new(current_account, limit: 100, test_only: test_mode?)
      .call
  end
end
