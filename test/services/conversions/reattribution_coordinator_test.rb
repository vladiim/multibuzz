# frozen_string_literal: true

require "test_helper"

module Conversions
  class ReattributionCoordinatorTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "marks the batch processing and enqueues one chunk job per slice" do
      batch = create_batch((1..250).to_a)

      assert_enqueued_jobs 3, only: Conversions::ReattributionChunkJob do
        Conversions::ReattributionCoordinator.new(batch).call
      end

      assert_predicate batch.reload, :processing?
    end

    test "completes a batch with no conversion ids without enqueuing" do
      batch = create_batch([])

      assert_no_enqueued_jobs do
        Conversions::ReattributionCoordinator.new(batch).call
      end

      assert_predicate batch.reload, :completed?
    end

    test "a second coordinator run does not re-enqueue chunks" do
      batch = create_batch((1..120).to_a)
      Conversions::ReattributionCoordinator.new(batch).call

      assert_no_enqueued_jobs do
        Conversions::ReattributionCoordinator.new(batch.reload).call
      end
    end

    private

    def create_batch(ids)
      accounts(:one).reattribution_batches.create!(
        trigger: :identity_merge, conversion_ids: ids, total: ids.size
      )
    end
  end
end
