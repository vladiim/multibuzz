# frozen_string_literal: true

module Conversions
  # Entry point for reattribution. Creates a ReattributionBatch and enqueues its
  # coordinator, coalescing a repeated trigger into an unfinished batch that
  # already covers the same conversions.
  module Reattribution
    def self.enqueue(account:, conversion_ids:, trigger:)
      ids = conversion_ids.compact.uniq.sort
      return if ids.empty?

      existing_batch(account, ids) || start_batch(account, ids, trigger)
    end

    def self.existing_batch(account, ids)
      account.reattribution_batches.unfinished.find_by(conversion_ids: ids)
    end

    def self.start_batch(account, ids, trigger)
      account.reattribution_batches.create!(
        trigger: trigger, conversion_ids: ids, total: ids.size
      ).tap { |batch| ReattributionCoordinatorJob.perform_later(batch.id) }
    end
  end
end
