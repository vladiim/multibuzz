# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      class NotEquals < Base
        # Case-sensitive, for parity with the SQL `=` comparison it negates.
        def self.matches?(candidate, value)
          candidate.to_s != value.to_s
        end

        private

        def apply_to_column(scope)
          scope.where.not(column_hash)
        end

        def apply_to_property(scope)
          scope.where.not(property_conditions, *values)
        end

        def property_conditions
          @property_conditions ||= values.map { "#{property_path} #{SQL_EQUALITY} #{SQL_PLACEHOLDER}" }.join(SQL_OR)
        end
      end
    end
  end
end
