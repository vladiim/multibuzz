# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      class Contains < Base
        private

        def apply_to_column(scope)
          scope.where(column_conditions, *like_values)
        end

        def apply_to_property(scope)
          scope.where(property_conditions, *like_values)
        end

        def column_conditions
          @column_conditions ||= values.map { "conversions.#{field} ILIKE ?" }.join(" OR ")
        end

        def property_conditions
          @property_conditions ||= values.map { "conversions.properties->>'#{sanitized_field}' ILIKE ?" }.join(" OR ")
        end

        def like_values
          @like_values ||= values.map { |v| "%#{v}%" }
        end
      end
    end
  end
end
