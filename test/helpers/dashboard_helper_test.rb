require "test_helper"

class DashboardHelperTest < ActionView::TestCase
  # percentage_change tests
  test "percentage_change calculates correct positive change" do
    assert_equal 50.0, percentage_change(150, 100)
  end

  test "percentage_change calculates correct negative change" do
    assert_equal(-25.0, percentage_change(75, 100))
  end

  test "percentage_change returns nil when current is nil" do
    assert_nil percentage_change(nil, 100)
  end

  test "percentage_change returns nil when prior is nil" do
    assert_nil percentage_change(100, nil)
  end

  test "percentage_change returns nil when prior is zero" do
    assert_nil percentage_change(100, 0)
  end

  # format_change tests
  test "format_change renders positive change in green" do
    result = format_change(25.5)
    assert_includes result, "text-green-600"
    assert_includes result, "25.5%"
  end

  test "format_change renders negative change in red" do
    result = format_change(-15.2)
    assert_includes result, "text-red-600"
    assert_includes result, "15.2%"
  end

  test "format_change renders em dash for nil" do
    result = format_change(nil)
    assert_includes result, "text-gray-400"
  end

  # format_metric tests
  test "format_metric formats number with delimiter" do
    assert_equal "1,234", format_metric(1234)
    assert_equal "1,000,000", format_metric(1000000)
  end

  test "format_metric formats currency" do
    assert_equal "$1,234", format_metric(1234, type: :currency)
  end

  test "format_metric formats percentage" do
    assert_equal "25.5%", format_metric(25.5, type: :percentage)
  end

  test "format_metric returns em dash for nil" do
    assert_equal "—", format_metric(nil)
    assert_equal "—", format_metric(nil, type: :currency)
    assert_equal "—", format_metric(nil, type: :percentage)
  end

  test "format_metric defaults to number for unknown type" do
    assert_equal "1,234", format_metric(1234, type: :unknown)
  end

  # attribution_model_description tests
  test "attribution_model_description returns correct description" do
    assert_equal "100% credit to the first marketing touchpoint", attribution_model_description("first_touch")
    assert_equal "100% credit to the last touchpoint before conversion", attribution_model_description("last_touch")
    assert_equal "Equal credit distributed across all touchpoints", attribution_model_description("linear")
  end

  test "attribution_model_description returns default for unknown algorithm" do
    assert_equal "Custom attribution model", attribution_model_description("unknown")
  end
end
