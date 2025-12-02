module Dashboard
  module Queries
    class FunnelStagesQuery
      # Display name overrides for common event types
      # Falls back to humanized event_type if not in this map
      DISPLAY_NAMES = {
        "page_view" => "Visits",
        "add_to_cart" => "Add to Cart",
        "checkout_started" => "Checkout Started",
        "purchase" => "Purchase"
      }.freeze

      def initialize(scope, unique_users: true)
        @scope = scope
        @unique_users = unique_users
      end

      def call
        stages_with_conversion_rates
      end

      private

      attr_reader :scope, :unique_users

      def stages_with_conversion_rates
        previous_total = nil

        ordered_stages.map do |stage_data|
          stage = build_stage(stage_data, previous_total)
          previous_total = stage[:total]
          stage
        end
      end

      def ordered_stages
        event_type_counts
          .sort_by { |_type, count| -count }
          .map { |event_type, count| { event_type: event_type, count: count } }
      end

      def event_type_counts
        @event_type_counts ||= unique_users ? unique_user_counts : total_event_counts
      end

      def unique_user_counts
        scope.group(:event_type).distinct.count(:visitor_id)
      end

      def total_event_counts
        scope.group(:event_type).count
      end

      def build_stage(stage_data, previous_total)
        event_type = stage_data[:event_type]
        total = stage_data[:count]

        {
          stage: display_name(event_type),
          event_type: event_type,
          total: total,
          by_channel: channel_breakdown(event_type),
          conversion_rate: conversion_rate(total, previous_total)
        }
      end

      def display_name(event_type)
        DISPLAY_NAMES[event_type] || event_type.humanize.titleize
      end

      def channel_breakdown(event_type)
        Channels::ALL.each_with_object({}) do |channel, result|
          result[channel] = channel_counts(event_type)[channel] || 0
        end
      end

      def channel_counts(event_type)
        @channel_counts ||= {}
        @channel_counts[event_type] ||= unique_users ? unique_channel_counts(event_type) : total_channel_counts(event_type)
      end

      def unique_channel_counts(event_type)
        scope
          .where(event_type: event_type)
          .joins(:session)
          .group("sessions.channel")
          .distinct
          .count(:visitor_id)
      end

      def total_channel_counts(event_type)
        scope
          .where(event_type: event_type)
          .joins(:session)
          .group("sessions.channel")
          .count
      end

      def conversion_rate(current_total, previous_total)
        return nil if previous_total.nil? || previous_total.zero?

        ((current_total.to_f / previous_total) * 100).round(1)
      end
    end
  end
end
