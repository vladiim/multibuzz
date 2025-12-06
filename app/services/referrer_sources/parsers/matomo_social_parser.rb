module ReferrerSources
  module Parsers
    class MatomoSocialParser < BaseParser
      private

      def parse
        yaml_data = YAML.safe_load(content) || {}
        yaml_data.flat_map { |source_name, domains| parse_network(source_name, domains) }
      rescue Psych::SyntaxError
        []
      end

      def parse_network(source_name, domains)
        Array(domains).map do |domain|
          build_record(
            domain: domain,
            source_name: source_name,
            medium: Mediums::SOCIAL,
            data_origin: DataOrigins::MATOMO_SOCIAL
          )
        end
      end
    end
  end
end
