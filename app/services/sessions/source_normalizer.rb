# frozen_string_literal: true

module Sessions
  class SourceNormalizer
    def self.call(value)
      new(value).call
    end

    def initialize(value)
      @value = value
    end

    def call
      return if value.blank?

      from_alias || from_canonical || from_fuzzy_match || downcased
    end

    private

    attr_reader :value

    def downcased
      @downcased ||= value.to_s.downcase.strip
    end

    def from_alias
      UtmAliases::SOURCES[downcased]
    end

    def from_canonical
      downcased if UtmAliases::CANONICAL_SOURCES.include?(downcased)
    end

    def from_fuzzy_match
      matcher.find_match(downcased)
    end

    def matcher
      @matcher ||= Text::LevenshteinMatcher.new(UtmAliases::CANONICAL_SOURCES)
    end
  end
end
