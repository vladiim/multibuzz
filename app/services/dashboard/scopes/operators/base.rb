# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      class Base
        COLUMN_FIELDS = %w[conversion_type funnel revenue].freeze

        def initialize(field:, values:)
          @field = field.to_s
          @values = Array(values)
        end

        def call(scope)
          return scope if field.blank? || values.empty?

          column_field? ? apply_to_column(scope) : apply_to_property(scope)
        end

        private

        attr_reader :field, :values

        def column_field?
          COLUMN_FIELDS.include?(field)
        end

        def sanitized_field
          @sanitized_field ||= field.gsub(/[^a-zA-Z0-9_]/, "")
        end

        def apply_to_column(scope)
          raise NotImplementedError
        end

        def apply_to_property(scope)
          raise NotImplementedError
        end
      end
    end
  end
end
