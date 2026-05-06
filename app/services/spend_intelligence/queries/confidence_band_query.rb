# frozen_string_literal: true

module SpendIntelligence
  module Queries
    # Per-channel ROAS spread across multiple attribution models — the
    # "confidence band" rendered on the spend dashboard's channel table.
    # Wide band (max/min ≫ 1) = models disagree; narrow = models agree.
    class ConfidenceBandQuery
      def initialize(spend_scope:, credits_scope_by_model:, selected_model:)
        @spend_scope = spend_scope
        @credits_scope_by_model = credits_scope_by_model
        @selected_model = selected_model
      end

      def by_channel
        @by_channel ||= bands.select(&:present?).each_with_object({}) { |band, acc| acc[band.channel] = band.to_h }
      end

      private

      attr_reader :spend_scope, :credits_scope_by_model, :selected_model

      def bands
        spend_by_channel.map { |channel, spend_micros| ChannelConfidenceBand.new(channel: channel, spend_micros: spend_micros, revenue_by_model: revenue_by_model_at(channel), selected_model: selected_model) }
      end

      def revenue_by_model_at(channel)
        revenue_by_channel_per_model.transform_values { |by_channel| by_channel[channel].to_f }
      end

      def revenue_by_channel_per_model
        @revenue_by_channel_per_model ||= credits_scope_by_model.transform_values { |scope| scope.group(:channel).sum(:revenue_credit) }
      end

      def spend_by_channel
        @spend_by_channel ||= spend_scope.group(:channel).sum(:spend_micros)
      end
    end
  end
end
