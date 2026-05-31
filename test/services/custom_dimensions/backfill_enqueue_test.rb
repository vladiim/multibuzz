# frozen_string_literal: true

require "test_helper"

# Dimension/rule changes enqueue an account backfill. See spec Phase 3.4.
class CustomDimensions::BackfillEnqueueTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creating a dimension enqueues a backfill for its account" do
    assert_enqueued_with(job: CustomDimensions::BackfillJob, args: [ account.id ]) do
      account.custom_dimensions.create!(key: "tier", name: "Tier")
    end
  end

  test "saving a rule enqueues a backfill" do
    dimension = account.custom_dimensions.create!(key: "tier", name: "Tier", mapping_mode: "campaign")

    assert_enqueued_with(job: CustomDimensions::BackfillJob, args: [ account.id ]) do
      dimension.dimension_rules.create!(
        account: account, position: 1, match_field: "campaign_name", operator: "contains", value: "x", output_value: "Y"
      )
    end
  end

  test "destroying a dimension enqueues a backfill" do
    dimension = account.custom_dimensions.create!(key: "tier", name: "Tier")

    assert_enqueued_with(job: CustomDimensions::BackfillJob, args: [ account.id ]) do
      dimension.destroy!
    end
  end

  def account = @account ||= accounts(:one)
end
