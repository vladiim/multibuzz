# frozen_string_literal: true

module Sessions
  class BotClassifier
    KNOWN_BOT = "known_bot"
    NO_SIGNALS = "no_signals"

    def initialize(user_agent:, referrer: nil, utm: {}, click_ids: {})
      @user_agent = user_agent
      @referrer = referrer
      @utm = utm || {}
      @click_ids = click_ids || {}
    end

    def call
      return known_bot_result if known_bot?
      return no_signals_result if no_signals?

      qualified_result
    end

    private

    attr_reader :user_agent, :referrer, :utm, :click_ids

    def known_bot?
      BotPatterns::Matcher.bot?(user_agent)
    end

    def no_signals?
      referrer.blank? &&
        utm.values.none?(&:present?) &&
        click_ids.empty?
    end

    def known_bot_result
      { suspect: true, suspect_reason: KNOWN_BOT }
    end

    def no_signals_result
      { suspect: true, suspect_reason: NO_SIGNALS }
    end

    def qualified_result
      { suspect: false, suspect_reason: nil }
    end
  end
end
