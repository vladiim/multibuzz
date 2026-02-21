# frozen_string_literal: true

module LiveEventsHelper
  FEED_BADGE_STYLES = {
    event:      { bg: "bg-indigo-100", text: "text-indigo-700" },
    conversion: { bg: "bg-green-100", text: "text-green-700" },
    identify:   { bg: "bg-purple-100", text: "text-purple-700" },
    session:    { bg: "bg-blue-100", text: "text-blue-700" },
    visitor:    { bg: "bg-gray-100", text: "text-gray-600" }
  }.freeze

  FEED_BADGE_INITIALS = {
    conversion: "$",
    identify:   "ID",
    session:    "S",
    visitor:    "V"
  }.freeze

  def feed_badge_class(feed_type)
    style = FEED_BADGE_STYLES.fetch(feed_type, FEED_BADGE_STYLES[:event])
    "w-8 h-8 rounded-full flex items-center justify-center text-xs font-semibold #{style[:bg]} #{style[:text]}"
  end

  def feed_badge_initial(feed_item)
    return FEED_BADGE_INITIALS[feed_item.feed_type] if FEED_BADGE_INITIALS.key?(feed_item.feed_type)

    feed_item.record.event_type.first.upcase
  end

  def feed_item_label(feed_item)
    case feed_item.feed_type
    when :event      then feed_item.record.event_type
    when :conversion then "conversion: #{feed_item.record.conversion_type}"
    when :identify   then "identify"
    when :session    then "session_started"
    when :visitor    then "visitor_created"
    end
  end

  def event_primary_info(event)
    props = event.properties || {}

    value = props["url"] || props["path"] || props["page"] ||
            props["revenue"] || props["name"] || props["value"] ||
            props.values.first

    return "" if value.nil?

    value.is_a?(Numeric) ? number_to_currency(value) : truncate(value.to_s, length: 60)
  end

  def conversion_primary_info(conversion)
    parts = []
    parts << number_to_currency(conversion.revenue) if conversion.revenue.present? && conversion.revenue > 0
    parts.join
  end

  def session_primary_info(session)
    parts = []
    utm = session.initial_utm || {}
    parts << utm["utm_source"] if utm["utm_source"].present?
    parts << session.initial_referrer if session.initial_referrer.present? && parts.empty?
    truncate(parts.join(" / "), length: 60)
  end

  def identify_primary_info(identity)
    parts = [ identity.external_id ]
    email = identity.traits&.dig("email")
    parts << email if email.present?
    truncate(parts.compact.join(" - "), length: 60)
  end

  def visitor_primary_info(visitor)
    truncate(visitor.visitor_id.to_s, length: 24)
  end

  def feed_item_json(feed_item)
    case feed_item.feed_type
    when :event      then event_json(feed_item.record)
    when :conversion then conversion_json(feed_item)
    when :identify   then identify_json(feed_item)
    when :session    then session_json(feed_item)
    when :visitor    then visitor_json(feed_item)
    end
  end

  private

  def event_json(event)
    {
      id: event.prefix_id,
      feed_type: "event",
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

  def conversion_json(feed_item)
    conv = feed_item.record
    {
      id: conv.prefix_id,
      feed_type: "conversion",
      event_type: "conversion: #{conv.conversion_type}",
      occurred_at: conv.converted_at.iso8601,
      occurred_at_formatted: conv.converted_at.strftime("%B %d, %Y at %I:%M:%S %p"),
      is_test: conv.is_test,
      channel: nil,
      session_id: conv.session_id,
      visitor_id: conv.visitor_id,
      properties: {
        conversion_type: conv.conversion_type,
        revenue: conv.revenue&.to_f
      }.compact
    }.to_json
  end

  def identify_json(feed_item)
    identity = feed_item.record
    {
      id: identity.prefix_id,
      feed_type: "identify",
      event_type: "identify",
      occurred_at: identity.last_identified_at.iso8601,
      occurred_at_formatted: identity.last_identified_at.strftime("%B %d, %Y at %I:%M:%S %p"),
      is_test: identity.respond_to?(:is_test) && identity.is_test,
      channel: nil,
      session_id: nil,
      visitor_id: nil,
      properties: {
        external_id: identity.external_id
      }.merge(identity.traits || {})
    }.to_json
  end

  def session_json(feed_item)
    sess = feed_item.record
    {
      id: sess.prefix_id,
      feed_type: "session",
      event_type: "session_started",
      occurred_at: sess.started_at.iso8601,
      occurred_at_formatted: sess.started_at.strftime("%B %d, %Y at %I:%M:%S %p"),
      is_test: sess.is_test,
      channel: sess.channel&.titleize,
      session_id: sess.session_id,
      visitor_id: sess.visitor&.visitor_id,
      properties: (sess.initial_utm || {}).merge(
        referrer: sess.initial_referrer,
        channel: sess.channel,
        page_views: sess.page_view_count
      ).compact
    }.to_json
  end

  def visitor_json(feed_item)
    vis = feed_item.record
    {
      id: vis.prefix_id,
      feed_type: "visitor",
      event_type: "visitor_created",
      occurred_at: vis.created_at.iso8601,
      occurred_at_formatted: vis.created_at.strftime("%B %d, %Y at %I:%M:%S %p"),
      is_test: vis.is_test,
      channel: nil,
      session_id: nil,
      visitor_id: vis.visitor_id,
      properties: (vis.traits || {}).merge(
        visitor_id: vis.visitor_id
      )
    }.to_json
  end
end
