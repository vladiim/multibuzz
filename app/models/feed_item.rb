# frozen_string_literal: true

# Lightweight value object for unified activity feed entries.
# Wraps records from different tables (events, conversions, identities,
# sessions, visitors) into a common interface for chronological display.
FeedItem = Struct.new(:feed_type, :occurred_at, :record, keyword_init: true) do
  TYPES = %i[event conversion identify session visitor].freeze

  def event?     = feed_type == :event
  def conversion? = feed_type == :conversion
  def identify?  = feed_type == :identify
  def session?   = feed_type == :session
  def visitor?   = feed_type == :visitor

  def prefix_id
    record.prefix_id
  end

  def test?
    record.respond_to?(:is_test) && record.is_test
  end
end
