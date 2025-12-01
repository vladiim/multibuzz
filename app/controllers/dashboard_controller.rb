class DashboardController < Dashboard::BaseController
  def show
    @account = current_account
    @stats = build_stats
    @recent_events = scoped_events.recent.limit(10)
    @utm_breakdown = utm_breakdown
  end

  private

  def build_stats
    {
      total_events: scoped_events.count,
      total_visitors: scoped_visitors.count,
      total_sessions: scoped_sessions.count,
      events_today: scoped_events.where("occurred_at >= ?", Time.current.beginning_of_day).count
    }
  end

  def utm_breakdown
    utm_counts
      .map { |(source, medium, campaign), count| build_utm_hash(source, medium, campaign, count) }
      .sort_by { |utm| -utm[:count] }
      .take(10)
  end

  def utm_counts
    scoped_events
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
