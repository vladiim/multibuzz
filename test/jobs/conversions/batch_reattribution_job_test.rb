# frozen_string_literal: true

require "test_helper"

module Conversions
  class BatchReattributionJobTest < ActiveSupport::TestCase
    test "calls ReattributionService for each conversion id passed in" do
      conversions = build_conversions(2)

      Conversions::BatchReattributionJob.new.perform(conversions.map(&:id))

      conversions.each do |conversion|
        assert_predicate conversion.attribution_credits.reload, :present?,
          "Expected credits for conversion #{conversion.id}"
      end
    end

    test "ignores conversion ids that no longer exist" do
      conversions = build_conversions(1)
      missing_id = conversions.last.id + 999_999

      assert_nothing_raised do
        Conversions::BatchReattributionJob.new.perform([ missing_id, conversions.first.id ])
      end

      assert_predicate conversions.first.attribution_credits.reload, :present?
    end

    test "no-ops with empty list" do
      assert_nothing_raised { Conversions::BatchReattributionJob.new.perform([]) }
    end

    private

    def build_conversions(count)
      visitor = visitors(:two)
      identity = identities(:one)
      visitor.update!(identity: identity)
      build_sessions_for(visitor)

      Array.new(count) do |i|
        Conversion.create!(
          account: visitor.account,
          visitor: visitor,
          identity: identity,
          conversion_type: "purchase",
          revenue: 10.00 + i,
          converted_at: Time.current,
          journey_session_ids: []
        )
      end
    end

    def build_sessions_for(visitor)
      Session.create!(
        account: visitor.account,
        visitor: visitor,
        session_id: SecureRandom.hex(16),
        started_at: 5.days.ago,
        channel: "organic_search",
        initial_utm: { "utm_source" => "google" }
      )
    end
  end
end
