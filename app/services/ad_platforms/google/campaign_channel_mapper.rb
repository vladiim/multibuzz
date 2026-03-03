# frozen_string_literal: true

module AdPlatforms
  module Google
    class CampaignChannelMapper
      DEFAULT_CHANNEL = Channels::PAID_SEARCH
      OVERRIDE_PREFIX = "campaign_"

      def self.call(campaign_type:, network_type: nil, campaign_id: nil, channel_overrides: {})
        return channel_overrides.fetch(override_key(campaign_id)) if override?(campaign_id, channel_overrides)

        campaign_type == AdPlatformChannels::PERFORMANCE_MAX ? map_pmax(network_type) : map_standard(campaign_type)
      end

      class << self
        private

        def override_key(campaign_id)
          "#{OVERRIDE_PREFIX}#{campaign_id}"
        end

        def override?(campaign_id, overrides)
          campaign_id && overrides.key?(override_key(campaign_id))
        end

        def map_standard(campaign_type)
          AdPlatformChannels::GOOGLE_CAMPAIGN_TYPE_MAP.fetch(campaign_type, DEFAULT_CHANNEL)
        end

        def map_pmax(network_type)
          return DEFAULT_CHANNEL if network_type.nil?

          AdPlatformChannels::GOOGLE_NETWORK_TYPE_MAP.fetch(network_type, DEFAULT_CHANNEL)
        end
      end
    end
  end
end
