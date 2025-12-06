module ReferrerSources
  module Parsers
    class MatomoSearchParser < BaseParser
      # Common TLDs to expand wildcard domains
      WILDCARD_TLDS = %w[
        com co.uk de fr es it nl be at ch
        ca au in jp br mx ru pl se no dk fi
      ].freeze

      private

      def parse
        yaml_data = YAML.safe_load(content) || {}
        yaml_data.flat_map { |source_name, config| parse_engine(source_name, config) }
      rescue Psych::SyntaxError
        []
      end

      def parse_engine(source_name, config)
        urls = config["urls"] || []
        keyword_param = config.dig("params")&.first

        urls.flat_map { |url| expand_url(url, source_name, keyword_param) }
      end

      def expand_url(url, source_name, keyword_param)
        if url.include?("{}")
          expand_wildcard(url, source_name, keyword_param)
        else
          [build_search_record(url, source_name, keyword_param)]
        end
      end

      def expand_wildcard(url_pattern, source_name, keyword_param)
        WILDCARD_TLDS.map do |tld|
          domain = url_pattern.gsub("{}", tld)
          build_search_record(domain, source_name, keyword_param)
        end
      end

      def build_search_record(domain, source_name, keyword_param)
        build_record(
          domain: domain,
          source_name: source_name,
          medium: Mediums::SEARCH,
          keyword_param: keyword_param,
          data_origin: DataOrigins::MATOMO_SEARCH
        )
      end
    end
  end
end
