# frozen_string_literal: true

require "test_helper"

class SpendHelperTest < ActionView::TestCase
  include SpendHelper

  # --- format_spend ---

  test "format_spend converts micros to dollars" do
    assert_equal "$12.40", format_spend(12_400_000)
  end

  test "format_spend returns $0.00 for zero" do
    assert_equal "$0.00", format_spend(0)
  end

  test "format_spend returns $0.00 for nil" do
    assert_equal "$0.00", format_spend(nil)
  end

  test "format_spend handles sub-dollar amounts" do
    assert_equal "$0.50", format_spend(500_000)
  end

  # --- spend_channel_color ---

  test "spend_channel_color returns correct hex for paid_search" do
    assert_equal "#6366F1", spend_channel_color("paid_search")
  end

  test "spend_channel_color returns correct hex for display" do
    assert_equal "#8B5CF6", spend_channel_color("display")
  end

  test "spend_channel_color returns fallback for unknown channel" do
    assert_equal "#9CA3AF", spend_channel_color("unknown_channel")
  end

  # --- spend_ctr ---

  test "spend_ctr calculates click-through rate" do
    row = { impressions: 1000, clicks: 50 }

    assert_equal "5.0%", spend_ctr(row)
  end

  test "spend_ctr returns dash for zero impressions" do
    row = { impressions: 0, clicks: 0 }

    assert_equal "—", spend_ctr(row)
  end

  test "spend_ctr handles nil impressions" do
    row = { impressions: nil, clicks: 10 }

    assert_equal "—", spend_ctr(row)
  end

  # --- spend_cpc ---

  test "spend_cpc formats cost per click" do
    row = { cpc_micros: 2_500_000 }

    assert_equal "$2.50", spend_cpc(row)
  end

  test "spend_cpc returns dash when nil" do
    row = { cpc_micros: nil }

    assert_equal "—", spend_cpc(row)
  end
end
