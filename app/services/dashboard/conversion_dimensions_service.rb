# frozen_string_literal: true

module Dashboard
  class ConversionDimensionsService < ApplicationService
    def initialize(account)
      @account = account
    end

    private

    attr_reader :account

    def run
      success_result(dimensions: dimensions)
    end

    def dimensions
      built_in_dimensions + property_dimensions
    end

    def built_in_dimensions
      [
        { key: "conversion_type", label: "Conversion Name", type: "column" },
        { key: "funnel", label: "Funnel", type: "column" },
        { key: "revenue", label: "Revenue", type: "numeric" }
      ]
    end

    def property_dimensions
      account
        .conversion_property_keys
        .by_popularity
        .recent
        .limit(20)
        .pluck(:property_key)
        .map { |key| build_property_dimension(key) }
    end

    def build_property_dimension(key)
      { key: key, label: key.titleize, type: "property" }
    end
  end
end
