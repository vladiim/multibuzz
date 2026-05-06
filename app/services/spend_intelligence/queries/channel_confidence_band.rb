# frozen_string_literal: true

module SpendIntelligence
  module Queries
    # Value object: one channel's ROAS spread across multiple attribution models.
    # Computes min/max/selected from a per-model revenue map and a single
    # spend-micros figure. `present?` filters out channels where no model produced
    # any credit (spread is undefined and the band would be hidden anyway).
    class ChannelConfidenceBand
      MICRO_UNIT = AdSpendRecord::MICRO_UNIT

      def initialize(channel:, spend_micros:, revenue_by_model:, selected_model:)
        @channel = channel
        @spend_micros = spend_micros
        @revenue_by_model = revenue_by_model
        @selected_model = selected_model
      end

      attr_reader :channel

      def present? = roas_by_model.any? && spend_units.positive?

      def to_h = { min: roas_values.min, max: roas_values.max, selected: roas_by_model[selected_model], by_model: roas_by_model }

      private

      attr_reader :spend_micros, :revenue_by_model, :selected_model

      def roas_by_model
        @roas_by_model ||= revenue_by_model
          .reject { |_model, revenue| revenue.to_f.zero? }
          .transform_values { |revenue| (revenue.to_f / spend_units).round(2) }
      end

      def roas_values = @roas_values ||= roas_by_model.values
      def spend_units = @spend_units ||= (spend_micros.to_d / MICRO_UNIT)
    end
  end
end
