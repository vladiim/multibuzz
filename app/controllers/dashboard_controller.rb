class DashboardController < ApplicationController
  before_action :require_login

  def show
    @account = current_user.primary_account
    @stats = build_stats
    @recent_events = @account.events.recent.limit(10)
    @utm_breakdown = utm_breakdown
  end

  private

  def build_stats
    {
      total_events: @account.events.count,
      total_visitors: @account.visitors.count,
      total_sessions: @account.sessions.count,
      events_today: @account.events.where("occurred_at >= ?", Time.current.beginning_of_day).count
    }
  end

  def utm_breakdown
    utm_counts
      .map { |(source, medium, campaign), count| build_utm_hash(source, medium, campaign, count) }
      .sort_by { |utm| -utm[:count] }
      .take(10)
  end

  def utm_counts
    @account.events
      .where.not("properties->>'utm_source' IS NULL")
      .group("properties->>'utm_source'", "properties->>'utm_medium'", "properties->>'utm_campaign'")
      .count
  end

  def build_utm_hash(source, medium, campaign, count)
    {
      utm_source: source,
      utm_medium: medium,
      utm_campaign: campaign,
      count: count
    }
  end
end
