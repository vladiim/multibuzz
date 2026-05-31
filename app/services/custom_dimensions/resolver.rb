# frozen_string_literal: true

module CustomDimensions
  # Pure resolver. Given the active dimensions for a connection plus that
  # connection's metadata baseline, produce { key => value } for one campaign
  # row. No side effects, no DB access of its own — the caller loads and scopes
  # the dimensions (ideally with `:dimension_rules` preloaded) once per sync.
  #
  # Composition (see lib/specs/custom_dimensions_spec.md):
  #   by-campaign : first matching rule's output, else connection value, else default
  #   by-account  : connection value, else default
  class Resolver
    # Build a resolver for one connection's sync: the account's active,
    # user-defined dimensions scoped to this platform, rules preloaded, with the
    # connection's metadata as the by-account baseline. Loads once per sync.
    def self.for_connection(connection)
      new(
        dimensions: connection.account.custom_dimensions.active.user_defined.for_platform(connection.platform).includes(:dimension_rules).to_a,
        connection_metadata: connection.metadata
      )
    end

    def initialize(dimensions:, connection_metadata: {})
      @dimensions = dimensions
      @connection_metadata = connection_metadata || {}
    end

    def call(row)
      dimensions.each_with_object({}) do |dimension, resolved|
        resolved[dimension.key] = resolve(dimension, row)
      end
    end

    private

    attr_reader :dimensions, :connection_metadata

    def resolve(dimension, row)
      matched = matching_rule(dimension, row) if dimension.by_campaign?
      return matched.output_value if matched

      connection_metadata[dimension.key].presence || dimension.default_value
    end

    def matching_rule(dimension, row)
      dimension.dimension_rules.sort_by(&:position).find { |rule| rule_matches?(rule, row) }
    end

    def rule_matches?(rule, row)
      candidate = row[DimensionRule::ROW_ATTRIBUTES[rule.match_field]]
      Dashboard::Scopes::Operators.matches?(operator: rule.operator, candidate: candidate, value: rule.value)
    end
  end
end
