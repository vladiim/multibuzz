# frozen_string_literal: true

module Dashboard
  class ConversionValuesService < ApplicationService
    COLUMN_FIELDS = %w[conversion_type funnel].freeze
    LIMIT = 20

    def initialize(account, field:, query: nil, test_mode: false)
      @account = account
      @field = field
      @query = query.to_s.strip.presence
      @test_mode = test_mode
    end

    private

    attr_reader :account, :field, :query, :test_mode

    def run
      return error_result(["field is required"]) if field.blank?

      success_result(values: values)
    end

    def values
      @values ||= column_field? ? column_values : property_values
    end

    def column_field?
      COLUMN_FIELDS.include?(field)
    end

    def column_values
      conversions_scope
        .where.not(field => nil)
        .distinct
        .limit(LIMIT)
        .then { |scope| filter_by_query(scope, field) }
        .pluck(field)
    end

    def property_values
      conversions_scope
        .where("jsonb_exists(properties, ?)", sanitized_field)
        .select(property_select_sql)
        .limit(LIMIT)
        .then { |scope| filter_property_by_query(scope) }
        .map(&:val)
        .compact
    end

    def conversions_scope
      @conversions_scope ||= test_mode ? account.conversions.test_data : account.conversions.production
    end

    def sanitized_field
      @sanitized_field ||= field.to_s.gsub(/[^a-zA-Z0-9_]/, "")
    end

    def property_select_sql
      Arel.sql("DISTINCT properties->>'#{sanitized_field}' as val")
    end

    def filter_by_query(scope, column)
      query ? scope.where("#{column} ILIKE ?", "%#{query}%") : scope
    end

    def filter_property_by_query(scope)
      query ? scope.where("properties->>'#{sanitized_field}' ILIKE ?", "%#{query}%") : scope
    end
  end
end
