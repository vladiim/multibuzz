# frozen_string_literal: true

module Dashboard
  module Scopes
    module Operators
      class Regex < Base
        # Evaluated in memory at sync/backfill only, never on the request path.
        # A bad pattern is treated as no-match so one rule can't abort a sync.
        def self.matches?(candidate, value)
          Regexp.new(value.to_s, Regexp::IGNORECASE).match?(candidate.to_s)
        rescue RegexpError
          false
        end

        private

        def apply_to_column(scope)
          scope.where(conditions(column_path(field)), *values)
        end

        def apply_to_property(scope)
          scope.where(conditions(property_path), *values)
        end

        def conditions(target)
          values.map { "#{target} #{SQL_REGEX_CI} #{SQL_PLACEHOLDER}" }.join(SQL_OR)
        end
      end
    end
  end
end
