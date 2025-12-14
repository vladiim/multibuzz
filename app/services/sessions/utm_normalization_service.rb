# frozen_string_literal: true

module Sessions
  class UtmNormalizationService
    def initialize(utm)
      @utm = symbolize_keys(utm)
    end

    def call
      return {} if utm.blank?

      {
        utm_source: SourceNormalizer.call(utm[:utm_source]),
        utm_medium: MediumNormalizer.call(utm[:utm_medium]),
        utm_campaign: downcase(utm[:utm_campaign]),
        utm_content: utm[:utm_content],
        utm_term: utm[:utm_term]
      }.compact
    end

    class << self
      def normalize_source(value)
        SourceNormalizer.call(value)
      end

      def normalize_medium(value)
        MediumNormalizer.call(value)
      end
    end

    private

    attr_reader :utm

    def symbolize_keys(hash)
      return {} if hash.blank?

      hash.to_h { |k, v| [k.to_s.to_sym, v] }
    end

    def downcase(value)
      value&.to_s&.downcase&.strip.presence
    end
  end
end
