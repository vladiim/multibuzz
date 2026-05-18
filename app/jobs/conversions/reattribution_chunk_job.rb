# frozen_string_literal: true

module Conversions
  class ReattributionChunkJob < ApplicationJob
    queue_as :reattribution

    def perform(batch_id, conversion_ids)
      ChunkReattribution.new(ReattributionBatch.find(batch_id), conversion_ids).call
    end
  end
end
