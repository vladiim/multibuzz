# frozen_string_literal: true

require "test_helper"

class ReattributionBatchTest < ActiveSupport::TestCase
  test "is valid with an account, trigger, and total" do
    assert_predicate batch, :valid?
  end

  test "defaults to pending" do
    assert_predicate batch, :pending?
  end

  test "requires a trigger" do
    assert_not ReattributionBatch.new(account: account, total: 1).valid?
  end

  test "mark_processing! sets the status and started_at" do
    batch.mark_processing!

    assert_predicate batch, :processing?
    assert_predicate batch.started_at, :present?
  end

  test "mark_completed! sets the status and completed_at" do
    batch.mark_completed!

    assert_predicate batch, :completed?
    assert_predicate batch.completed_at, :present?
  end

  test "mark_failed! sets the status and completed_at" do
    batch.mark_failed!

    assert_predicate batch, :failed?
    assert_predicate batch.completed_at, :present?
  end

  test "increment_processed! advances the processed counter" do
    batch.increment_processed!(3)

    assert_equal 3, batch.reload.processed
  end

  test "increment_failed! advances the failed counter" do
    batch.increment_failed!(2)

    assert_equal 2, batch.reload.failed
  end

  test "unfinished scope excludes completed and failed batches" do
    completed = ReattributionBatch.create!(
      account: account, trigger: :billing_unlock, total: 1, status: :completed
    )

    assert_includes ReattributionBatch.unfinished, batch
    assert_not_includes ReattributionBatch.unfinished, completed
  end

  test "exposes a prefixed id" do
    assert_match(/\Arbatch_/, batch.prefix_id)
  end

  private

  def account = @account ||= accounts(:one)

  def batch
    @batch ||= ReattributionBatch.create!(account: account, trigger: :identity_merge, total: 5)
  end
end
