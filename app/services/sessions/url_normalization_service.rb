# frozen_string_literal: true

module Sessions
  class UrlNormalizationService
    def self.call(url, strip_query: false)
      new(url, strip_query: strip_query).call
    end

    def initialize(url, strip_query: false)
      @url = url
      @strip_query = strip_query
    end

    def call
      return if url.blank?

      parsed? ? normalize_parsed_url : url.to_s.strip
    end

    private

    attr_reader :url, :strip_query

    def parsed?
      parsed_uri.present?
    end

    def parsed_uri
      @parsed_uri ||= parse_uri
    end

    def parse_uri
      URI.parse(url.to_s.strip)
    rescue URI::InvalidURIError
      nil
    end

    def normalize_parsed_url
      [ normalized_host, normalized_path.to_s.delete_suffix("/"), normalized_query ]
        .compact
        .join
    end

    def normalized_host
      host = parsed_uri.host&.downcase
      return unless host

      host = host.delete_prefix("www.")
      port_suffix = non_standard_port? ? ":#{parsed_uri.port}" : ""
      "#{host}#{port_suffix}"
    end

    def normalized_path
      parsed_uri.path.presence
    end

    def normalized_query
      return if strip_query
      return unless parsed_uri.query.present?

      "?#{parsed_uri.query}"
    end

    def non_standard_port?
      port = parsed_uri.port
      return false unless port

      !standard_port?(port)
    end

    def standard_port?(port)
      port == 80 || port == 443
    end
  end
end
