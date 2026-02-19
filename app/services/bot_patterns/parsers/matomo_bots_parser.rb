# frozen_string_literal: true

module BotPatterns
  module Parsers
    class MatomoBotsParser < BaseParser
      REGEX_KEY = "regex"
      NAME_KEY = "name"

      private

      def parse
        entries = YAML.safe_load(content) || []
        entries.filter_map { |entry| parse_entry(entry) }
      rescue Psych::SyntaxError
        []
      end

      def parse_entry(entry)
        pattern = entry[REGEX_KEY]
        return unless pattern.present?

        build_record(pattern: pattern, name: entry[NAME_KEY] || pattern)
      end
    end
  end
end
