# frozen_string_literal: true

module Conversions
  class ReattributionJob < ApplicationJob
    queue_as :default

    def perform(conversion_id)
      ReattributionService.new(Conversion.find(conversion_id)).call
    end
  end
end
