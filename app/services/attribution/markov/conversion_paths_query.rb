# frozen_string_literal: true

module Attribution
  module Markov
    # Fetches channel paths from historical conversions for Markov Chain attribution.
    #
    # Returns an array of channel sequences, e.g.:
    #   [["organic_search", "email", "paid_search"], ["paid_search"], ...]
    #
    # Sessions for every conversion's journey are loaded in one batched query
    # rather than one query per conversion (the 2026-05-18 reattribution N+1).
    #
    class ConversionPathsQuery
      include BurstDeduplication

      SESSION_LOAD_BATCH_SIZE = 10_000
      CACHE_TTL = 10.minutes
      MAX_PATHS = 5_000

      # Per-account cache so a reattribution or model-rerun burst computes the
      # full account's paths once, not once per conversion.
      def self.cached_for(account)
        Rails.cache.fetch("attribution/conversion_paths/#{account.id}", expires_in: CACHE_TTL) do
          new(account).call
        end
      end

      def initialize(account, max_paths: MAX_PATHS)
        @account = account
        @max_paths = max_paths
      end

      def call
        conversions
          .map { |conversion| deduped_channel_path(conversion) }
          .reject(&:empty?)
      end

      private

      attr_reader :account, :max_paths

      def conversions
        @conversions ||= cap(account.conversions.where.not(journey_session_ids: []).to_a)
      end

      # Bounds the in-Ruby cost of the Markov / Shapley algorithms, which scale
      # with the path count (Shapley is O(2^channels) per path).
      def cap(records)
        records.size > max_paths ? records.sample(max_paths) : records
      end

      def deduped_channel_path(conversion)
        touchpoints = sessions_for(conversion).map do |session|
          { session_id: session.id, channel: session.channel, occurred_at: session.started_at }
        end

        collapse_burst_sessions(touchpoints).map { |touchpoint| touchpoint[:channel] }
      end

      def sessions_for(conversion)
        conversion.journey_session_ids
          .filter_map { |id| sessions_by_id[id] }
          .sort_by(&:started_at)
      end

      def sessions_by_id
        @sessions_by_id ||= journey_sessions.index_by(&:id)
      end

      def journey_sessions
        all_journey_session_ids.each_slice(SESSION_LOAD_BATCH_SIZE).flat_map do |ids|
          account.sessions.qualified.where.not(channel: nil).where(id: ids).to_a
        end
      end

      def all_journey_session_ids
        conversions.flat_map(&:journey_session_ids).uniq
      end
    end
  end
end
