# frozen_string_literal: true

module Conversions
  class ReattributionChunkJob < ApplicationJob
    queue_as :reattribution

    # One chunk per batch at a time, so a single account's reattribution
    # cannot occupy every thread on the reattribution worker. The duration
    # exceeds ChunkReattribution::BUDGET so the limit holds for a full chunk.
    limits_concurrency to: 1, key: ->(batch_id, _conversion_ids) { batch_id }, duration: 15.minutes

    def perform(batch_id, conversion_ids)
      ChunkReattribution.new(ReattributionBatch.find(batch_id), conversion_ids).call
    end
  end
end
