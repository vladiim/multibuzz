# frozen_string_literal: true

require "test_helper"

module Conversions
  class ChunkReattributionTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    test "reattributes each conversion and advances the processed counter" do
      Conversions::ChunkReattribution.new(batch, [ conversion.id ]).call

      assert_equal 1, batch.reload.processed
    end

    test "completes the batch once every conversion is accounted for" do
      Conversions::ChunkReattribution.new(batch, [ conversion.id ]).call

      assert_predicate batch.reload, :completed?
    end

    test "counts a missing conversion as failed so the batch still completes" do
      Conversions::ChunkReattribution.new(batch, [ -1 ]).call

      assert_equal 1, batch.reload.failed
      assert_predicate batch.reload, :completed?
    end

    test "re-enqueues the remainder when the wall-clock budget is spent" do
      assert_enqueued_with(
        job: Conversions::ReattributionChunkJob, args: [ batch.id, [ conversion.id ] ]
      ) do
        Conversions::ChunkReattribution.new(batch, [ conversion.id ], deadline: 1.hour.ago).call
      end

      assert_equal 0, batch.reload.processed
    end

    test "does nothing once the batch is already completed" do
      Conversions::ChunkReattribution.new(batch, [ conversion.id ]).call

      assert_predicate batch.reload, :completed?

      Conversions::ChunkReattribution.new(batch, [ conversion.id ]).call

      assert_equal 1, batch.reload.processed
    end

    private

    def batch
      @batch ||= account.reattribution_batches.create!(
        trigger: :identity_merge, conversion_ids: [ conversion.id ], total: 1
      )
    end

    def account = @account ||= conversion.account

    def conversion
      @conversion ||= begin
        visitor = visitors(:two)
        visitor.update!(identity: identities(:one))
        Session.create!(
          account: visitor.account, visitor: visitor, session_id: SecureRandom.hex(16),
          started_at: 5.days.ago, channel: "organic_search"
        )
        Conversion.create!(
          account: visitor.account, visitor: visitor, identity: identities(:one),
          conversion_type: "purchase", revenue: 100, converted_at: Time.current,
          journey_session_ids: []
        )
      end
    end
  end
end
