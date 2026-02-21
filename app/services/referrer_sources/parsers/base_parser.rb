# frozen_string_literal: true

module ReferrerSources
  module Parsers
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
        raise NotImplementedError, "Subclasses must implement #parse"
      end

      def build_record(domain:, source_name:, medium:, keyword_param: nil, is_spam: false, data_origin:)
        {
          domain: domain,
          source_name: source_name,
          medium: medium,
          keyword_param: keyword_param,
          is_spam: is_spam,
          data_origin: data_origin
        }
      end
    end
  end
end
