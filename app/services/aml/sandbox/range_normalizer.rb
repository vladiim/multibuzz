# frozen_string_literal: true

module AML
  module Sandbox
    class RangeNormalizer
      NORMALIZERS = {
        Range => ->(v) { v },
        ActiveSupport::Duration => ->(v) { 0.seconds..v },
        Integer => ->(v) { 0.seconds..v.seconds },
        Float => ->(v) { 0.seconds..v.seconds }
      }.freeze

      def self.normalize(value)
        new(value).call
      end

      def initialize(value)
        @value = value
      end

      def call
        normalizer&.call(@value) || invalid_type_error
      end

      private

      def normalizer
        NORMALIZERS.find { |type, _| @value.is_a?(type) }&.last
      end

      def invalid_type_error
        raise ::AML::ValidationError.new(
          "Invalid window range: #{@value.inspect}",
          suggestion: "Use a duration (30.days) or range (30.days..60.days)"
        )
      end
    end
  end
end
