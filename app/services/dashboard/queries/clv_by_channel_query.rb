module Dashboard
  module Queries
    class ClvByChannelQuery
      def initialize(account:, acquisition_conversions:, test_mode: false)
        @account = account
        @acquisition_conversions = acquisition_conversions
        @test_mode = test_mode
      end

      def call
        return [] if acquisition_conversions.empty?

        channels_with_clv.sort_by { |c| -c[:clv] }
      end

      private

      attr_reader :account, :acquisition_conversions, :test_mode

      def channels_with_clv
        channel_groups.map { |channel, identity_ids| build_channel_stats(channel, identity_ids) }
      end

      def build_channel_stats(channel, identity_ids)
        {
          channel: channel,
          clv: calculate_clv(identity_ids),
          customers: identity_ids.size,
          revenue: revenue_for_identities(identity_ids)
        }
      end

      def calculate_clv(identity_ids)
        customer_count = identity_ids.size
        return 0 unless customer_count.positive?

        (revenue_for_identities(identity_ids) / customer_count).round(2)
      end

      def channel_groups
        @channel_groups ||= acquisition_credits
          .group_by { |credit| credit[:channel] }
          .transform_values { |credits| credits.pluck(:identity_id).uniq }
      end

      def acquisition_credits
        @acquisition_credits ||= AttributionCredit
          .joins(:conversion)
          .where(conversion_id: acquisition_conversions.pluck(:id))
          .where(attribution_model: primary_model)
          .pluck(:channel, "conversions.identity_id")
          .map { |channel, identity_id| { channel: channel, identity_id: identity_id } }
      end

      def revenue_for_identities(identity_ids)
        @revenue_cache ||= {}
        cache_key = identity_ids.sort.join(",")

        @revenue_cache[cache_key] ||= account.conversions
          .where(identity_id: identity_ids)
          .then { |scope| test_mode ? scope.test_data : scope.production }
          .sum(:revenue)
          .to_f
      end

      def primary_model
        @primary_model ||= account.attribution_models.active.find_by(is_default: true) ||
          account.attribution_models.active.first
      end
    end
  end
end
