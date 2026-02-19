# frozen_string_literal: true

module BotPatterns
  module Sources
    CRAWLER_USER_AGENTS = "crawler_user_agents"
    MATOMO_BOTS = "matomo_bots"
    CUSTOM = "custom"

    ALL = [
      CRAWLER_USER_AGENTS,
      MATOMO_BOTS,
      CUSTOM
    ].freeze

    CRAWLER_USER_AGENTS_URL = "https://raw.githubusercontent.com/monperrus/crawler-user-agents/master/crawler-user-agents.json"
    MATOMO_BOTS_URL = "https://raw.githubusercontent.com/matomo-org/device-detector/master/regexes/bots.yml"

    CACHE_KEY = "bot_patterns/compiled"
    CUSTOM_CONFIG_PATH = "config/bot_patterns.yml"
  end
end
