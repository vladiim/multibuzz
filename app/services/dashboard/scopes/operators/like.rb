# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      # Shared base for ILIKE-based operators (contains / starts_with / ends_with).
      # Subclasses define just two things, both expressing the same intent:
      #   - `.pattern(value)`  : how the value is wrapped for the SQL ILIKE clause
      #   - `.matches?(c, v)`  : the equivalent in-memory match (case-insensitive)
      # Abstract: not used directly.
      class Like < Base
        private

        def apply_to_column(scope)
          scope.where(conditions(column_path(field)), *patterns)
        end

        def apply_to_property(scope)
          scope.where(conditions(property_path), *patterns)
        end

        def conditions(target)
          values.map { "#{target} #{SQL_ILIKE} #{SQL_PLACEHOLDER}" }.join(SQL_OR)
        end

        def patterns
          @patterns ||= values.map { |value| self.class.pattern(value) }
        end
      end
    end
  end
end
