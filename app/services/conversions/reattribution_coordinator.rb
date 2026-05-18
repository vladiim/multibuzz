# frozen_string_literal: true

module Conversions
  # Slices a ReattributionBatch's conversions into bounded chunk jobs on the
  # :reattribution queue. One coordinator per batch; no per-conversion fan-out.
  class ReattributionCoordinator
    CHUNK_SIZE = 100

    def initialize(batch)
      @batch = batch
    end

    def call
      return unless claim_batch

      batch.conversion_ids.empty? ? batch.mark_completed! : ActiveJob.perform_all_later(chunk_jobs)
    end

    private

    attr_reader :batch

    # Atomically claim the batch so a duplicate coordinator cannot enqueue a
    # second set of chunk jobs for the same batch.
    def claim_batch
      batch.with_lock { batch.pending? && batch.mark_processing! }
    end

    def chunk_jobs
      batch.conversion_ids.each_slice(CHUNK_SIZE).map do |ids|
        ReattributionChunkJob.new(batch.id, ids)
      end
    end
  end
end
