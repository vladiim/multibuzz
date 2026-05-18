# frozen_string_literal: true

module Conversions
  class ReattributionCoordinatorJob < ApplicationJob
    queue_as :reattribution

    def perform(batch_id)
      ReattributionCoordinator.new(ReattributionBatch.find(batch_id)).call
    end
  end
end
