# frozen_string_literal: true

module ReferrerSources
  module Parsers
    class SnowplowParser < BaseParser
      MEDIUM_MAPPING = {
        "search" => Mediums::SEARCH,
        "social" => Mediums::SOCIAL,
        "email" => Mediums::EMAIL
      }.freeze

      private

      def parse
        json_data = JSON.parse(content)
        json_data.flat_map { |medium_key, sources| parse_medium(medium_key, sources) }
      rescue JSON::ParserError
        []
      end

      def parse_medium(medium_key, sources)
        medium = MEDIUM_MAPPING[medium_key]
        return [] unless medium

        sources.flat_map { |source_name, config| parse_source(source_name, config, medium) }
      end

      def parse_source(source_name, config, medium)
        domains = config["domains"] || []
        keyword_param = config.dig("parameters")&.first

        domains.map do |domain|
          build_record(
            domain: domain,
            source_name: source_name,
            medium: medium,
            keyword_param: keyword_param,
            data_origin: DataOrigins::SNOWPLOW
          )
        end
      end
    end
  end
end
