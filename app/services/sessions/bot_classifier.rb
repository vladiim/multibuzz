# frozen_string_literal: true

module Sessions
  class BotClassifier
    KNOWN_BOT = "known_bot"
    SPAM_REFERRER = "spam_referrer"
    NO_SIGNALS = "no_signals"

    SPAM_REFERRER_DOMAINS = %w[
      binance.com
      shsupplychain.com
    ].freeze

    IP_ADDRESS = /\A\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\z/

    def initialize(user_agent:, referrer: nil, utm: {}, click_ids: {})
      @user_agent = user_agent
      @referrer = referrer
      @utm = utm || {}
      @click_ids = click_ids || {}
    end

    def call
      return known_bot_result if known_bot?
      return spam_referrer_result if spam_referrer?
      return no_signals_result if no_signals?

      qualified_result
    end

    private

    attr_reader :user_agent, :referrer, :utm, :click_ids

    def known_bot?
      BotPatterns::Matcher.bot?(user_agent)
    end

    def spam_referrer?
      return false if referrer.blank?

      raw_ip_referrer? || known_spam_domain?
    end

    def raw_ip_referrer?
      referrer_host&.match?(IP_ADDRESS)
    end

    def known_spam_domain?
      return false unless normalized_host

      SPAM_REFERRER_DOMAINS.any? { |d| normalized_host == d || normalized_host.end_with?(".#{d}") }
    end

    def normalized_host
      @normalized_host ||= referrer_host&.downcase&.sub(/\Awww\./, "")
    end

    def referrer_host
      @referrer_host ||= extract_host
    end

    def extract_host
      url = referrer.include?("://") ? referrer : "https://#{referrer}"
      URI.parse(url).host
    rescue URI::InvalidURIError
      nil
    end

    def no_signals?
      referrer.blank? &&
        utm.values.none?(&:present?) &&
        click_ids.empty?
    end

    def known_bot_result
      { suspect: true, suspect_reason: KNOWN_BOT }
    end

    def spam_referrer_result
      { suspect: true, suspect_reason: SPAM_REFERRER }
    end

    def no_signals_result
      { suspect: true, suspect_reason: NO_SIGNALS }
    end

    def qualified_result
      { suspect: false, suspect_reason: nil }
    end
  end
end
