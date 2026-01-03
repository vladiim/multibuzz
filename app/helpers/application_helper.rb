module ApplicationHelper
  # Format event limits for display (500000 -> "500K", 1000000 -> "1M")
  def format_event_limit(count)
    if count >= Billing::EVENTS_PER_MILLION
      "#{count / Billing::EVENTS_PER_MILLION}M"
    else
      "#{count / Billing::EVENTS_PER_THOUSAND}K"
    end
  end

  # Formatted free event limit for marketing copy
  def free_event_limit_display
    format_event_limit(Billing::FREE_EVENT_LIMIT)
  end

  # Full number with delimiter (500000 -> "500,000")
  def free_event_limit_full
    number_with_delimiter(Billing::FREE_EVENT_LIMIT)
  end
end
