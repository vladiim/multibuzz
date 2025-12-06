module LiveEventsHelper
  def event_type_badge_class(event_type)
    # Simple color based on first letter hash for visual variety
    hue = event_type.bytes.sum % 360
    "w-8 h-8 rounded-full flex items-center justify-center bg-gray-100 text-gray-600"
  end

  def event_type_initial(event_type)
    event_type.first.upcase
  end

  def event_primary_info(event)
    props = event.properties || {}

    # Try common property names in order of preference
    value = props["url"] || props["path"] || props["page"] ||
            props["revenue"] || props["name"] || props["value"] ||
            props.values.first

    return "" if value.nil?

    if value.is_a?(Numeric)
      number_to_currency(value)
    else
      truncate(value.to_s, length: 60)
    end
  end

  def event_json(event)
    {
      id: event.prefix_id,
      event_type: event.event_type,
      occurred_at: event.occurred_at.iso8601,
      occurred_at_formatted: event.occurred_at.strftime("%B %d, %Y at %I:%M:%S %p"),
      is_test: event.is_test,
      channel: event.session&.channel&.titleize,
      session_id: event.session&.session_id,
      visitor_id: event.visitor_id,
      properties: event.properties
    }.to_json
  end
end
