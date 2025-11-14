module Sessions
  class ChannelAttributionService
    # Hash key constants
    UTM_MEDIUM_KEY = :utm_medium
    UTM_SOURCE_KEY = :utm_source

    # UTM medium patterns mapped to channels
    UTM_MEDIUM_PATTERNS = {
      /^(cpc|ppc|paid)$/i => Channels::PAID_SEARCH,
      /^social$/i => ->(service) { service.social_channel },
      /^(email|e-mail)$/i => Channels::EMAIL,
      /^(display|banner)$/i => Channels::DISPLAY,
      /^(affiliate|affiliates)$/i => Channels::AFFILIATE,
      /^(referral|partner)$/i => Channels::REFERRAL,
      /^organic$/i => Channels::ORGANIC_SEARCH,
      /^video$/i => Channels::VIDEO
    }.freeze

    # Referrer domain patterns mapped to channels
    REFERRER_DOMAIN_PATTERNS = {
      Channels::SEARCH_ENGINES => Channels::ORGANIC_SEARCH,
      Channels::SOCIAL_NETWORKS => Channels::ORGANIC_SOCIAL,
      Channels::VIDEO_PLATFORMS => Channels::VIDEO
    }.freeze

    def initialize(utm_data, referrer)
      @utm_data = utm_data || {}
      @referrer = referrer
    end

    def call
      return channel_from_utm if utm_present?
      return channel_from_referrer if referrer_domain.present?

      Channels::DIRECT
    end

    # Public method for lambda callback in UTM_MEDIUM_PATTERNS
    def social_channel
      paid_social? ? Channels::PAID_SOCIAL : Channels::ORGANIC_SOCIAL
    end

    private

    attr_reader :utm_data, :referrer

    def utm_present?
      utm_data.present? && utm_data.any?
    end

    def channel_from_utm
      UTM_MEDIUM_PATTERNS
        .find { |pattern, _| utm_medium&.match?(pattern) }
        .then { |match| match ? resolve_channel(match.last) : Channels::OTHER }
    end

    def resolve_channel(value)
      value.respond_to?(:call) ? value.call(self) : value
    end

    def paid_social?
      utm_source&.match?(Channels::SOCIAL_NETWORKS)
    end

    def utm_medium
      utm_data[UTM_MEDIUM_KEY] || utm_data[UTM_MEDIUM_KEY.to_s]
    end

    def utm_source
      utm_data[UTM_SOURCE_KEY] || utm_data[UTM_SOURCE_KEY.to_s]
    end

    def channel_from_referrer
      REFERRER_DOMAIN_PATTERNS
        .find { |pattern, _| referrer_domain&.match?(pattern) }
        .then { |match| match ? match.last : Channels::REFERRAL }
    end

    def referrer_domain
      return nil if referrer.blank?

      @referrer_domain ||= URI.parse(referrer).host
    rescue URI::InvalidURIError
      nil
    end
  end
end
