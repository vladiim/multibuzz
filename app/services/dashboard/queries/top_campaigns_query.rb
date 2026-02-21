# frozen_string_literal: true

module Dashboard
  module Queries
    class TopCampaignsQuery
      DEFAULT_CHANNEL_LIMIT = 3
      DEFAULT_CAMPAIGN_LIMIT = 5

      def initialize(scope, channel_limit: DEFAULT_CHANNEL_LIMIT, campaign_limit: DEFAULT_CAMPAIGN_LIMIT)
        @scope = scope
        @channel_limit = channel_limit
        @campaign_limit = campaign_limit
      end

      def call
        top_channels.each_with_object({}) do |channel, result|
          result[channel] = campaigns_for(channel)
        end
      end

      private

      attr_reader :scope, :channel_limit, :campaign_limit

      def top_channels
        @top_channels ||= scope
          .group(:channel)
          .order("SUM(credit) DESC")
          .limit(channel_limit)
          .pluck(:channel)
      end

      def campaigns_for(channel)
        scope
          .where(channel: channel)
          .where.not(utm_campaign: [ nil, "" ])
          .group(:utm_campaign)
          .select(:utm_campaign, "SUM(credit) as total_credits", "SUM(revenue_credit) as total_revenue")
          .order("SUM(credit) DESC")
          .limit(campaign_limit)
          .map { |row| build_campaign_row(row) }
      end

      def build_campaign_row(row)
        {
          name: row.utm_campaign,
          conversions: row.total_credits.to_f,
          revenue: row.total_revenue.to_f
        }
      end
    end
  end
end
