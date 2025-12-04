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

    # Referrer domain patterns mapped to channels (fallback)
    REFERRER_DOMAIN_PATTERNS = {
      Channels::SEARCH_ENGINES => Channels::ORGANIC_SEARCH,
      Channels::SOCIAL_NETWORKS => Channels::ORGANIC_SOCIAL,
      Channels::VIDEO_PLATFORMS => Channels::VIDEO
    }.freeze

    # Map ReferrerSource mediums to Channels constants
    MEDIUM_TO_CHANNEL = {
      ReferrerSources::Mediums::SEARCH => Channels::ORGANIC_SEARCH,
      ReferrerSources::Mediums::SOCIAL => Channels::ORGANIC_SOCIAL,
      ReferrerSources::Mediums::EMAIL => Channels::EMAIL,
      ReferrerSources::Mediums::VIDEO => Channels::VIDEO,
      ReferrerSources::Mediums::SHOPPING => Channels::REFERRAL,
      ReferrerSources::Mediums::NEWS => Channels::REFERRAL
    }.freeze

    def initialize(utm_data, referrer)
      @utm_data = utm_data || {}
      @referrer = referrer
    end

    def call
      return channel_from_utm_or_fallback if utm_medium.present?
      return channel_from_utm_source if utm_source.present?
      return channel_from_referrer if referrer_domain.present?

      Channels::DIRECT
    end

    # Public method for lambda callback in UTM_MEDIUM_PATTERNS
    def social_channel
      paid_social? ? Channels::PAID_SOCIAL : Channels::ORGANIC_SOCIAL
    end

    private

    attr_reader :utm_data, :referrer

    def channel_from_utm_or_fallback
      match = UTM_MEDIUM_PATTERNS.find { |pattern, _| utm_medium.match?(pattern) }
      return resolve_channel(match.last) if match

      # utm_medium doesn't match known patterns - fall back to referrer or other
      return channel_from_referrer if referrer_domain.present?

      Channels::OTHER
    end

    def channel_from_utm_source
      # When only utm_source is present (no utm_medium), infer channel from source
      return Channels::ORGANIC_SEARCH if utm_source.match?(Channels::SEARCH_ENGINES)
      return Channels::ORGANIC_SOCIAL if utm_source.match?(Channels::SOCIAL_NETWORKS)
      return Channels::VIDEO if utm_source.match?(Channels::VIDEO_PLATFORMS)

      Channels::OTHER
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
      channel_from_lookup || channel_from_patterns
    end

    def channel_from_lookup
      return nil unless referrer_lookup
      return Channels::OTHER if referrer_lookup[:is_spam]

      MEDIUM_TO_CHANNEL.fetch(referrer_lookup[:medium], Channels::REFERRAL)
    end

    def referrer_lookup
      @referrer_lookup ||= ReferrerSources::LookupService.new(referrer).call
    end

    def channel_from_patterns
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
