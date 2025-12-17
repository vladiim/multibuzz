# frozen_string_literal: true

module Attribution
  module Markov
    # Fetches channel paths from historical conversions for Markov Chain attribution.
    #
    # Returns an array of channel sequences, e.g.:
    #   [["organic_search", "email", "paid_search"], ["paid_search"], ...]
    #
    class ConversionPathsQuery
      def initialize(account)
        @account = account
      end

      def call
        conversions_with_journeys
          .map { |conversion| channel_path_for(conversion) }
          .reject(&:empty?)
      end

      private

      attr_reader :account

      def conversions_with_journeys
        account
          .conversions
          .where.not(journey_session_ids: [])
      end

      def channel_path_for(conversion)
        sessions_for(conversion)
          .order(started_at: :asc)
          .where.not(channel: nil)
          .pluck(:channel)
      end

      def sessions_for(conversion)
        account.sessions.where(id: conversion.journey_session_ids)
      end
    end
  end
end
