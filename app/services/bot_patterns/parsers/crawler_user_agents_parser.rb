# frozen_string_literal: true

module BotPatterns
  module Parsers
    class CrawlerUserAgentsParser < BaseParser
      PATTERN_KEY = "pattern"

      private

      def parse
        entries = JSON.parse(content)
        entries.filter_map { |entry| parse_entry(entry) }
      rescue JSON::ParserError
        []
      end

      def parse_entry(entry)
        pattern = entry[PATTERN_KEY]
        return unless pattern.present?

        build_record(pattern: pattern, name: pattern)
      end
    end
  end
end
