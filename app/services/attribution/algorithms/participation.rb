# frozen_string_literal: true

module Attribution
  module Algorithms
    class Participation
      FULL_CREDIT = 1.0

      def initialize(touchpoints)
        @touchpoints = touchpoints
      end

      def call
        return [] if touchpoints.empty?

        unique_channels.map { |channel| build_credit_for_channel(channel) }
      end

      private

      attr_reader :touchpoints

      def unique_channels
        touchpoints.map { |tp| tp[:channel] }.uniq
      end

      def build_credit_for_channel(channel)
        touchpoint = first_touchpoint_for_channel(channel)

        {
          session_id: touchpoint[:session_id],
          channel: channel,
          credit: FULL_CREDIT
        }
      end

      def first_touchpoint_for_channel(channel)
        touchpoints.find { |tp| tp[:channel] == channel }
      end
    end
  end
end
