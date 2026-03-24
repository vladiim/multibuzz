# frozen_string_literal: true

require "test_helper"

module SpendIntelligence
  class RecommendationServiceTest < ActiveSupport::TestCase
    test "returns scale when marginal ROAS exceeds scale threshold" do
      result = recommend(roas: 3.5, marginal_roas: 2.0, spend: 10_000)

      assert_equal "scale", result[:action]
    end

    test "returns maintain when marginal ROAS is between thresholds" do
      result = recommend(roas: 2.5, marginal_roas: 1.1, spend: 10_000)

      assert_equal "maintain", result[:action]
    end

    test "returns reduce when marginal ROAS is below reduce threshold" do
      result = recommend(roas: 1.5, marginal_roas: 0.5, spend: 10_000)

      assert_equal "reduce", result[:action]
    end

    test "scale includes positive change amount" do
      result = recommend(roas: 3.5, marginal_roas: 2.0, spend: 10_000)

      assert_predicate result[:change_amount], :positive?
    end

    test "reduce includes negative change amount" do
      result = recommend(roas: 1.5, marginal_roas: 0.5, spend: 10_000)

      assert_predicate result[:change_amount], :negative?
    end

    test "maintain has zero change amount" do
      result = recommend(roas: 2.5, marginal_roas: 1.1, spend: 10_000)

      assert_equal 0, result[:change_amount]
    end

    test "includes channel and rationale" do
      result = recommend(roas: 3.5, marginal_roas: 2.0, spend: 10_000, channel: "paid_search")

      assert_equal "paid_search", result[:channel]
      assert_kind_of String, result[:rationale]
      assert_predicate result[:rationale], :present?
    end

    test "includes roas and marginal_roas" do
      result = recommend(roas: 3.5, marginal_roas: 2.0, spend: 10_000)

      assert_in_delta(3.5, result[:roas])
      assert_in_delta(2.0, result[:marginal_roas])
    end

    private

    def recommend(roas:, marginal_roas:, spend:, channel: "paid_search")
      RecommendationService.recommend(
        channel: channel,
        roas: roas,
        marginal_roas: marginal_roas,
        current_spend: spend
      )
    end
  end
end
