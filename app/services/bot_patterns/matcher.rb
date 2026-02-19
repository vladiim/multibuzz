# frozen_string_literal: true

module BotPatterns
  class Matcher
    CACHE_KEY = Sources::CACHE_KEY

    class << self
      def bot?(user_agent)
        return false if user_agent.blank?
        return false unless compiled_regex

        compiled_regex.match?(user_agent)
      end

      def bot_name(user_agent)
        return nil if user_agent.blank?
        return nil unless patterns_loaded?

        matched = pattern_list.find { |p| Regexp.new(p[:pattern], Regexp::IGNORECASE).match?(user_agent) }
        matched&.fetch(:name)
      end

      def load!(patterns)
        @pattern_list = patterns.freeze
        @compiled_regex = compile(patterns)
      end

      def reset!
        @pattern_list = nil
        @compiled_regex = nil
      end

      private

      def compiled_regex
        @compiled_regex || load_from_cache
      end

      def pattern_list
        @pattern_list || []
      end

      def patterns_loaded?
        pattern_list.any?
      end

      def load_from_cache
        cached = Rails.cache.read(CACHE_KEY)
        return nil unless cached

        load!(cached)
        @compiled_regex
      end

      def compile(patterns)
        return nil if patterns.empty?

        regexes = patterns.map { |p| Regexp.new(p[:pattern], Regexp::IGNORECASE) }
        Regexp.union(regexes)
      rescue RegexpError
        nil
      end
    end
  end
end
