module ReferrerSources
  module Parsers
    class MatomoSpamParser < BaseParser
      private

      def parse
        content
          .lines
          .map(&:strip)
          .reject { |line| line.blank? || line.start_with?("#") }
          .map { |domain| build_spam_record(domain) }
      end

      def build_spam_record(domain)
        build_record(
          domain: domain,
          source_name: domain,
          medium: Mediums::SOCIAL,
          is_spam: true,
          data_origin: DataOrigins::MATOMO_SPAM
        )
      end
    end
  end
end
