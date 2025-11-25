# frozen_string_literal: true

module Conversions
  class AttributionCalculationJob < ApplicationJob
    queue_as :default

    def perform(conversion_id)
      AttributionCalculationService.new(Conversion.find(conversion_id)).call
    end
  end
end
