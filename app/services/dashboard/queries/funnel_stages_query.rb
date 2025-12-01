module Dashboard
  module Queries
    class FunnelStagesQuery
      # Maps event_type to display name
      STAGES = {
        "page_view" => "Visits",
        "add_to_cart" => "Add to Cart",
        "checkout_started" => "Checkout Started",
        "purchase" => "Purchase"
      }.freeze

      def initialize(scope)
        @scope = scope
      end

      def call
        previous_total = nil

        STAGES.map do |event_type, stage_name|
          stage_data = build_stage(event_type, stage_name, previous_total)
          previous_total = stage_data[:total]
          stage_data
        end
      end

      private

      attr_reader :scope

      def build_stage(event_type, stage_name, previous_total)
        total = stage_total(event_type)

        {
          stage: stage_name,
          total: total,
          by_channel: channel_breakdown(event_type),
          conversion_rate: conversion_rate(total, previous_total)
        }
      end

      def stage_total(event_type)
        scope.where(event_type: event_type).count
      end

      def channel_breakdown(event_type)
        Channels::ALL.each_with_object({}) do |channel, result|
          result[channel] = channel_counts(event_type)[channel] || 0
        end
      end

      def channel_counts(event_type)
        @channel_counts ||= {}
        @channel_counts[event_type] ||= scope
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
