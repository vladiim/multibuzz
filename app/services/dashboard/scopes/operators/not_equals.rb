# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      class NotEquals < Base
        private

        def apply_to_column(scope)
          scope.where.not(conversions: { field => values })
        end

        def apply_to_property(scope)
          scope.where.not(property_conditions, *values)
        end

        def property_conditions
          @property_conditions ||= values.map { "conversions.properties->>'#{sanitized_field}' = ?" }.join(" OR ")
        end
      end
    end
  end
end
