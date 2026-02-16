# frozen_string_literal: true

module Attribution
  module Markov
    # Fetches channel paths from historical conversions for Markov Chain attribution.
    #
    # Returns an array of channel sequences, e.g.:
    #   [["organic_search", "email", "paid_search"], ["paid_search"], ...]
    #
    class ConversionPathsQuery
      include BurstDeduplication

      def initialize(account)
        @account = account
      end

      def call
        conversions_with_journeys
          .map { |conversion| deduped_channel_path(conversion) }
          .reject(&:empty?)
      end

      private

      attr_reader :account

      def conversions_with_journeys
        account
          .conversions
          .where.not(journey_session_ids: [])
      end

      def deduped_channel_path(conversion)
        touchpoints = sessions_for(conversion)
          .qualified
          .where.not(channel: nil)
          .order(started_at: :asc)
          .map { |s| { session_id: s.id, channel: s.channel, occurred_at: s.started_at } }

        collapse_burst_sessions(touchpoints).map { |tp| tp[:channel] }
      end

      def sessions_for(conversion)
        account.sessions.where(id: conversion.journey_session_ids)
      end
    end
  end
end
