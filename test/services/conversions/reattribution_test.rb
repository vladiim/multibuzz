# frozen_string_literal: true

require "test_helper"

module Conversions
  class ReattributionTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "creates a batch and enqueues the coordinator" do
      assert_enqueued_with(job: Conversions::ReattributionCoordinatorJob) do
        Conversions::Reattribution.enqueue(
          account: account, conversion_ids: [ 3, 1, 2 ], trigger: :identity_merge
        )
      end
    end

    test "the batch records the sorted conversion ids, total, and trigger" do
      batch = Conversions::Reattribution.enqueue(
        account: account, conversion_ids: [ 3, 1, 2 ], trigger: :identity_merge
      )

      assert_equal [ 1, 2, 3 ], batch.conversion_ids
      assert_equal 3, batch.total
      assert_predicate batch, :identity_merge?
    end

    test "coalesces a duplicate trigger into the existing unfinished batch" do
      first = Conversions::Reattribution.enqueue(
        account: account, conversion_ids: [ 1, 2 ], trigger: :identity_merge
      )

      assert_no_difference -> { ReattributionBatch.count } do
        second = Conversions::Reattribution.enqueue(
          account: account, conversion_ids: [ 2, 1 ], trigger: :identity_merge
        )

        assert_equal first.id, second.id
      end
    end

    test "returns nil for an empty conversion set" do
      assert_nil Conversions::Reattribution.enqueue(
        account: account, conversion_ids: [], trigger: :identity_merge
      )
    end

    private

    def account = @account ||= accounts(:one)
  end
end
