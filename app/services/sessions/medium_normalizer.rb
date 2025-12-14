# frozen_string_literal: true

module Sessions
  class MediumNormalizer
    def self.call(value)
      new(value).call
    end

    def initialize(value)
      @value = value
    end

    def call
      return if value.blank?

      from_normalized_alias || from_original_alias || downcased
    end

    private

    attr_reader :value

    def downcased
      @downcased ||= value.to_s.downcase.strip
    end

    def normalized
      @normalized ||= downcased.parameterize(separator: "_")
    end

    def from_normalized_alias
      UtmAliases::MEDIUMS[normalized]
    end

    def from_original_alias
      UtmAliases::MEDIUMS[downcased]
    end
  end
end
