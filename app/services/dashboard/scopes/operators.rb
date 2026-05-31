# frozen_string_literal: true

module Dashboard
  module Scopes
    # Single source of truth for matching semantics. Each operator class supports
    # two evaluation modes, defined side by side so they can't drift:
    #   - SQL:    instance `#call(scope)` builds a WHERE clause (dashboard filters)
    #   - scalar: class `.matches?(candidate, value)` matches one string in memory
    #             (custom-dimension rule resolution — see CustomDimensions::Resolver)
    #
    # To add an operator: drop a class in operators/ that defines `.matches?` (and,
    # if it filters SQL, the private apply_* hooks). The dispatcher and the rule
    # model pick it up with no further wiring.
    module Operators
      # --- Operator slugs (slug.camelize => operator class name) ---
      EQUALS = "equals"
      NOT_EQUALS = "not_equals"
      CONTAINS = "contains"
      STARTS_WITH = "starts_with"
      ENDS_WITH = "ends_with"
      REGEX = "regex"

      # Operators valid for in-memory string matching, in UI order. Numeric SQL
      # operators (greater_than / less_than) are excluded — they define no
      # `.matches?`. The rule model validates `operator` against this list.
      MATCHABLE = [ EQUALS, NOT_EQUALS, CONTAINS, STARTS_WITH, ENDS_WITH, REGEX ].freeze

      # --- SQL fragments ---
      SQL_EQUALITY = "="
      SQL_ILIKE = "ILIKE"
      SQL_REGEX_CI = "~*" # Postgres case-insensitive POSIX match
      SQL_PLACEHOLDER = "?"
      SQL_OR = " OR "
      WILDCARD = "%"

      # Match a single string. Returns false for unknown or non-scalar operators
      # rather than raising — the rule model restricts input to MATCHABLE.
      def self.matches?(operator:, candidate:, value:)
        klass = "#{name}::#{operator.to_s.camelize}".safe_constantize
        return false unless klass.respond_to?(:matches?)

        klass.matches?(candidate, value)
      end
    end
  end
end
