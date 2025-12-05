module Dashboard
  module Queries
    class JourneyMetricsByChannel
      def initialize(scope)
        @scope = scope
      end

      def avg_channels_by_channel
        @avg_channels_by_channel ||= compute_averages(channels_per_conversion)
      end

      def avg_visits_by_channel
        @avg_visits_by_channel ||= compute_averages(visits_per_conversion)
      end

      private

      attr_reader :scope

      def compute_averages(per_conversion_counts)
        conversion_ids_by_channel.transform_values do |conversion_ids|
          values = conversion_ids.filter_map { |id| per_conversion_counts[id] }
          values.empty? ? nil : (values.sum.to_f / values.size).round(1)
        end
      end

      def conversion_ids_by_channel
        @conversion_ids_by_channel ||= scope
          .group(:channel)
          .pluck(:channel, Arel.sql("ARRAY_AGG(DISTINCT conversion_id)"))
          .to_h
      end

      def channels_per_conversion
        @channels_per_conversion ||= scope
          .group(:conversion_id)
          .distinct
          .count(:channel)
      end

      def visits_per_conversion
        @visits_per_conversion ||= scope
          .group(:conversion_id)
          .count
      end
    end
  end
end
