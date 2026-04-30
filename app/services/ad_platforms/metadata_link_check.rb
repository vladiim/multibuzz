# frozen_string_literal: true

module AdPlatforms
  # Confirms whether a connection's metadata mapping (e.g. Location: Eumundi-Noosa)
  # has any matching conversions in the same account, so the connection detail
  # page can warn the user when their spend won't roll up against anything.
  #
  # Returns one of:
  #   { state: :no_metadata }           — connection has no metadata, nothing to check
  #   { state: :linked,    count: N }   — N matching conversions in the last 90 days
  #   { state: :unlinked,  hint: "..." } — 0 exact matches; hint may suggest a near-miss value
  class MetadataLinkCheck
    LOOKBACK_DAYS = 90

    def initialize(connection)
      @connection = connection
      @account = connection.account
    end

    def call
      return { state: :no_metadata } if connection.metadata_pair.nil?

      key, value = connection.metadata_pair
      exact = exact_match_count(key, value)

      return { state: :linked, key: key, value: value, count: exact } if exact.positive?

      { state: :unlinked, key: key, value: value, hint: case_insensitive_hint(key, value) }
    end

    private

    attr_reader :connection, :account

    def exact_match_count(key, value)
      account.conversions
        .where("converted_at >= ?", LOOKBACK_DAYS.days.ago)
        .where("properties->>? = ?", key, value)
        .count
    end

    def case_insensitive_hint(key, value)
      key_extract = Arel.sql("properties->>#{ActiveRecord::Base.connection.quote(key)}")

      near_miss_values = account.conversions
        .where("converted_at >= ?", LOOKBACK_DAYS.days.ago)
        .where("LOWER(properties->>?) = ?", key, value.downcase)
        .pluck(key_extract)

      counts = near_miss_values.tally.reject { |v, _| v == value }
      matched_value, count = counts.max_by { |_, n| n }
      return nil unless matched_value

      { suggested_value: matched_value, count: count }
    end
  end
end
