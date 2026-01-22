# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      class Equals < Base
        private

        def apply_to_column(scope)
          scope.where(column_hash)
        end

        def apply_to_property(scope)
          scope.where(property_conditions, *values)
        end

        def property_conditions
          @property_conditions ||= values.map { "#{property_path} = ?" }.join(" OR ")
        end
      end
    end
  end
end
