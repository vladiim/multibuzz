# frozen_string_literal: true

module AdPlatforms
  module Meta
    class CampaignChannelMapper
      DEFAULT_CHANNEL = Channels::PAID_SOCIAL
      OVERRIDE_PREFIX = "campaign_"

      def self.call(campaign_id:, channel_overrides: nil)
        return DEFAULT_CHANNEL if channel_overrides.blank? || campaign_id.nil?

        channel_overrides.fetch("#{OVERRIDE_PREFIX}#{campaign_id}", DEFAULT_CHANNEL)
      end
    end
  end
end
