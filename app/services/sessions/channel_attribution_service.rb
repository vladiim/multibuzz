module Sessions
  class ChannelAttributionService
    # Hash key constants
    UTM_MEDIUM_KEY = :utm_medium
    UTM_SOURCE_KEY = :utm_source

    # UTM medium patterns mapped to channels
    UTM_MEDIUM_PATTERNS = {
      /^paid_social$/i => Channels::PAID_SOCIAL,
      /^paid$/i => ->(service) { service.paid_channel },
      /^(cpc|ppc)$/i => Channels::PAID_SEARCH,
      /^social$/i => ->(service) { service.social_channel },
      /^(email|e-mail)$/i => Channels::EMAIL,
      /^(display|banner)$/i => Channels::DISPLAY,
      /^(affiliate|affiliates)$/i => Channels::AFFILIATE,
      /^(referral|partner)$/i => Channels::REFERRAL,
      /^organic$/i => Channels::ORGANIC_SEARCH,
      /^video$/i => Channels::VIDEO,
      /^ai$/i => Channels::AI
    }.freeze

    # Referrer domain patterns mapped to channels (fallback)
    REFERRER_DOMAIN_PATTERNS = {
      Channels::AI_ENGINES => Channels::AI,
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
      ReferrerSources::Mediums::NEWS => Channels::REFERRAL,
      ReferrerSources::Mediums::AI => Channels::AI
    }.freeze

    def initialize(utm_data, referrer, click_ids = {}, page_host: nil)
      @utm_data = utm_data || {}
      @referrer = referrer
      @click_ids = click_ids || {}
      @page_host = page_host
    end

    def call
      # GA4-aligned classification hierarchy:
      # 1. Click identifiers (most reliable signal for paid traffic)
      # 2. UTM parameters (explicit tagging)
      # 3. Referrer patterns (fallback)
      return channel_from_click_ids if click_ids.any?
      return Channels::ORGANIC_SEARCH if plcid_present?
      return channel_from_utm_or_fallback if utm_medium.present?
      return channel_from_utm_source if utm_source.present?
      return Channels::DIRECT if internal_referrer?
      return channel_from_referrer if referrer_domain.present?

      Channels::DIRECT
    end

    # Public methods for lambda callbacks in UTM_MEDIUM_PATTERNS
    def social_channel
      social_source? ? Channels::PAID_SOCIAL : Channels::ORGANIC_SOCIAL
    end

    def paid_channel
      social_source? ? Channels::PAID_SOCIAL : Channels::PAID_SEARCH
    end

    private

    attr_reader :utm_data, :referrer, :click_ids, :page_host

    def channel_from_utm_or_fallback
      match = UTM_MEDIUM_PATTERNS.find { |pattern, _| utm_medium.match?(pattern) }
      return resolve_channel(match.last) if match

      # utm_medium doesn't match known patterns - fall back to referrer or other
      return channel_from_referrer if referrer_domain.present?

      Channels::OTHER
    end

    def channel_from_utm_source
      # When only utm_source is present (no utm_medium), infer channel from source
      return Channels::AI if utm_source.match?(Channels::AI_ENGINES)
      return Channels::ORGANIC_SEARCH if utm_source.match?(Channels::SEARCH_ENGINES)
      return Channels::ORGANIC_SOCIAL if utm_source.match?(Channels::SOCIAL_NETWORKS)
      return Channels::VIDEO if utm_source.match?(Channels::VIDEO_PLATFORMS)

      Channels::OTHER
    end

    def resolve_channel(value)
      value.respond_to?(:call) ? value.call(self) : value
    end

    def social_source?
      utm_source&.match?(Channels::SOCIAL_NETWORKS)
    end

    def channel_from_click_ids
      ClickIdCaptureService.infer_channel(click_ids) || Channels::OTHER
    end

    def utm_medium
      utm_data[UTM_MEDIUM_KEY] || utm_data[UTM_MEDIUM_KEY.to_s]
    end

    def utm_source
      utm_data[UTM_SOURCE_KEY] || utm_data[UTM_SOURCE_KEY.to_s]
    end

    def utm_term
      utm_data[:utm_term] || utm_data["utm_term"]
    end

    def plcid_present?
      ClickIdentifiers.plcid?(utm_term)
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

      @referrer_domain ||= extract_domain_from_referrer
    end

    def extract_domain_from_referrer
      # Handle URLs without protocol (e.g., "google.com" or "www.google.com")
      url = referrer.include?("://") ? referrer : "https://#{referrer}"
      URI.parse(url).host
    rescue URI::InvalidURIError
      nil
    end

    def internal_referrer?
      return false unless page_host.present?
      return false unless referrer_domain.present?

      normalize_host(referrer_domain) == normalize_host(page_host)
    end

    def normalize_host(host)
      host.to_s.downcase.sub(/^www\./, "").sub(/:\d+$/, "")
    end
  end
end
