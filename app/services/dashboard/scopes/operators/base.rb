# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      class Base
        COLUMN_FIELDS = %w[conversion_type funnel revenue].freeze

        # table_name: nil for direct conversion queries, "conversions" for joined scopes
        def initialize(field:, values:, table_name: "conversions")
          @field = field.to_s
          @values = Array(values)
          @table_name = table_name
        end

        def call(scope)
          return scope if field.blank? || values.empty?

          column_field? ? apply_to_column(scope) : apply_to_property(scope)
        end

        private

        attr_reader :field, :values, :table_name

        def column_field?
          COLUMN_FIELDS.include?(field)
        end

        def sanitized_field
          @sanitized_field ||= field.gsub(/[^a-zA-Z0-9_]/, "")
        end

        def property_path
          # Properties are stored flat at root level: { "location" => "Sydney" }
          # NOT nested: { "properties" => { "location" => "Sydney" } }
          table_name ? "#{table_name}.properties->>'#{sanitized_field}'" : "properties->>'#{sanitized_field}'"
        end

        def column_hash
          table_name ? { table_name.to_sym => { field => values } } : { field => values }
        end

        def column_path(column)
          table_name ? "#{table_name}.#{column}" : column
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
