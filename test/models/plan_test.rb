# frozen_string_literal: true

require "test_helper"

class PlanTest < ActiveSupport::TestCase
  test "recommended_for_ad_spend returns starter for sub-$25k tiers" do
    assert_equal plans(:starter), Plan.recommended_for_ad_spend("under_5k")
    assert_equal plans(:starter), Plan.recommended_for_ad_spend("5k_25k")
  end

  test "recommended_for_ad_spend returns growth for $25k-$100k" do
    assert_equal plans(:growth), Plan.recommended_for_ad_spend("25k_100k")
  end

  test "recommended_for_ad_spend returns pro for $100k+" do
    assert_equal plans(:pro), Plan.recommended_for_ad_spend("over_100k")
  end

  test "recommended_for_ad_spend falls back to growth for unknown tiers" do
    assert_equal plans(:growth), Plan.recommended_for_ad_spend("other")
    assert_equal plans(:growth), Plan.recommended_for_ad_spend(nil)
  end
end
