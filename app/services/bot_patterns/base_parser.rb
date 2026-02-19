# frozen_string_literal: true

module BotPatterns
  class BaseParser
    def initialize(content)
      @content = content
    end

    def call
      return [] if content.blank?

      parse
    end

    private

    attr_reader :content

    def parse
      raise NotImplementedError
    end

    def build_record(pattern:, name:)
      { pattern: pattern, name: name }
    end
  end
end
