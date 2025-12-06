module Dashboard
  module Queries
    class FunnelStagesQuery
      # Display name overrides for common event types
      # Falls back to humanized event_type if not in this map
      DISPLAY_NAMES = {
        "page_view" => "Page Views",
        "add_to_cart" => "Add to Cart",
        "checkout_started" => "Checkout Started",
        "purchase" => "Purchase"
      }.freeze

      def initialize(events_scope, sessions_scope: nil, conversions_scope: nil, unique_users: true)
        @events_scope = events_scope
        @sessions_scope = sessions_scope
        @conversions_scope = conversions_scope
        @unique_users = unique_users
      end

      def call
        stages_with_conversion_rates
      end

      private

      attr_reader :events_scope, :sessions_scope, :conversions_scope, :unique_users

      def stages_with_conversion_rates
        previous_total = nil

        all_stages.map do |stage_data|
          stage = build_stage(stage_data, previous_total)
          previous_total = stage[:total]
          stage
        end
      end

      def all_stages
        [visits_stage, *event_stages, conversions_stage].compact.reject { |s| s[:count].zero? }
      end

      # Visits stage from sessions

      def visits_stage
        return nil unless sessions_scope

        { stage_type: :visits, count: visits_count }
      end

      def visits_count
        @visits_count ||= unique_users ? unique_visitors_count : total_sessions_count
      end

      def unique_visitors_count
        sessions_scope.distinct.count(:visitor_id)
      end

      def total_sessions_count
        sessions_scope.count
      end

      # Event stages

      def event_stages
        event_type_counts
          .sort_by { |_type, count| -count }
          .map { |event_type, count| { stage_type: :event, event_type: event_type, count: count } }
      end

      def event_type_counts
        @event_type_counts ||= unique_users ? unique_event_user_counts : total_event_counts
      end

      def unique_event_user_counts
        events_scope.group(:event_type).distinct.count(:visitor_id)
      end

      def total_event_counts
        events_scope.group(:event_type).count
      end

      # Conversions stage

      def conversions_stage
        return nil unless conversions_scope

        { stage_type: :conversions, count: conversions_count }
      end

      def conversions_count
        @conversions_count ||= unique_users ? unique_conversion_visitors : total_conversions
      end

      def unique_conversion_visitors
        conversions_scope.distinct.count(:visitor_id)
      end

      def total_conversions
        conversions_scope.count
      end

      # Stage building

      def build_stage(stage_data, previous_total)
        case stage_data[:stage_type]
        when :visits
          build_visits_stage(stage_data, previous_total)
        when :conversions
          build_conversions_stage(stage_data, previous_total)
        else
          build_event_stage(stage_data, previous_total)
        end
      end

      def build_visits_stage(stage_data, previous_total)
        {
          stage: "Visits",
          event_type: nil,
          total: stage_data[:count],
          by_channel: visits_channel_breakdown,
          conversion_rate: conversion_rate(stage_data[:count], previous_total)
        }
      end

      def build_conversions_stage(stage_data, previous_total)
        {
          stage: "Conversions",
          event_type: nil,
          total: stage_data[:count],
          by_channel: conversions_channel_breakdown,
          conversion_rate: conversion_rate(stage_data[:count], previous_total)
        }
      end

      def build_event_stage(stage_data, previous_total)
        event_type = stage_data[:event_type]

        {
          stage: display_name(event_type),
          event_type: event_type,
          total: stage_data[:count],
          by_channel: event_channel_breakdown(event_type),
          conversion_rate: conversion_rate(stage_data[:count], previous_total)
        }
      end

      def display_name(event_type)
        DISPLAY_NAMES[event_type] || event_type.humanize.titleize
      end

      # Channel breakdowns

      def visits_channel_breakdown
        @visits_channel_breakdown ||= channel_hash_from(visits_channel_counts)
      end

      def visits_channel_counts
        @visits_channel_counts ||= unique_users ? sessions_scope.group(:channel).distinct.count(:visitor_id) : sessions_scope.group(:channel).count
      end

      def conversions_channel_breakdown
        @conversions_channel_breakdown ||= channel_hash_from(conversions_channel_counts)
      end

      def conversions_channel_counts
        # Use raw join since belongs_to :session is disabled for TimescaleDB
        @conversions_channel_counts ||= begin
          joined = conversions_scope.joins("INNER JOIN sessions ON sessions.id = conversions.session_id")
          unique_users ? joined.group("sessions.channel").distinct.count(:visitor_id) : joined.group("sessions.channel").count
        end
      end

      def channel_hash_from(counts)
        Channels::ALL.each_with_object({}) { |ch, result| result[ch] = counts[ch] || 0 }
      end

      def event_channel_breakdown(event_type)
        channel_hash_from(event_channel_counts(event_type))
      end

      def event_channel_counts(event_type)
        @event_channel_counts ||= {}
        @event_channel_counts[event_type] ||= unique_users ? unique_event_channel_counts(event_type) : total_event_channel_counts(event_type)
      end

      def unique_event_channel_counts(event_type)
        events_scope
          .where(event_type: event_type)
          .joins(:session)
          .group("sessions.channel")
          .distinct
          .count(:visitor_id)
      end

      def total_event_channel_counts(event_type)
        events_scope
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
