# frozen_string_literal: true

# Enqueues a per-account custom-dimensions backfill whenever a dimension or one
# of its rules changes, so historical spend rows pick up the new mapping. Shared
# by CustomDimension and DimensionRule (both expose account_id).
module EnqueuesDimensionBackfill
  extend ActiveSupport::Concern

  included do
    after_commit :enqueue_dimension_backfill, on: %i[create update destroy]
  end

  private

  def enqueue_dimension_backfill
    CustomDimensions::BackfillJob.perform_later(account_id)
  end
end
