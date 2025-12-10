# frozen_string_literal: true

module Sessions
  class ClickIdCaptureService
    def initialize(url: nil, properties: nil)
      @url = url
      @properties = properties || {}
    end

    def call
      ClickIdentifiers::ALL
        .each_with_object({}) { |id, result| capture_click_id(id, result) }
        .compact
    end

    class << self
      def infer_source(click_ids)
        first_click_id(click_ids)&.then { |id| ClickIdentifiers::SOURCE_MAP[id] }
      end

      def infer_channel(click_ids)
        first_click_id(click_ids)&.then { |id| ClickIdentifiers::CHANNEL_MAP[id] }
      end

      private

      def first_click_id(click_ids)
        ClickIdentifiers::ALL.find { |id| click_ids[id.to_sym].present? }
      end
    end

    private

    attr_reader :url, :properties

    def capture_click_id(id, result)
      value = from_url(id) || from_properties(id)
      result[id.to_sym] = value if value.present?
    end

    def from_url(id)
      url_params[id]
    end

    def from_properties(id)
      properties[id] || properties[id.to_sym]
    end

    def url_params
      @url_params ||= parsed_uri&.query ? URI.decode_www_form(parsed_uri.query).to_h : {}
    end

    def parsed_uri
      @parsed_uri ||= parse_uri
    end

    def parse_uri
      return if url.blank?

      URI.parse(url.to_s)
    rescue URI::InvalidURIError
      nil
    end
  end
end
