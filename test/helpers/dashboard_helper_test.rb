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

  test "format_metric rounds floats to one decimal place" do
    assert_equal "503.1", format_metric(503.0774)
    assert_equal "1,234.6", format_metric(1234.5678)
    assert_equal "0.3", format_metric(0.3333)
  end

  test "format_metric preserves integers without decimal" do
    assert_equal "503", format_metric(503)
    assert_equal "1,234", format_metric(1234)
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

  # hidden_filter_params tests
  test "hidden_filter_params preserves conversion_filters array of hashes" do
    @filter_params = {
      date_range: "30d",
      conversion_filters: [
        { field: "location", operator: "equals", values: ["Port Melbourne"] }
      ]
    }

    result = hidden_filter_params

    # Should generate properly indexed nested inputs
    assert_includes result, 'name="conversion_filters[0][field]"'
    assert_includes result, 'value="location"'
    assert_includes result, 'name="conversion_filters[0][operator]"'
    assert_includes result, 'value="equals"'
    assert_includes result, 'name="conversion_filters[0][values][]"'
    assert_includes result, 'value="Port Melbourne"'
  end

  test "hidden_filter_params preserves multiple conversion_filters" do
    @filter_params = {
      conversion_filters: [
        { field: "location", operator: "equals", values: ["Sydney"] },
        { field: "plan", operator: "equals", values: ["pro", "enterprise"] }
      ]
    }

    result = hidden_filter_params

    # First filter
    assert_includes result, 'name="conversion_filters[0][field]"'
    assert_includes result, 'name="conversion_filters[0][values][]"'

    # Second filter
    assert_includes result, 'name="conversion_filters[1][field]"'
    assert_includes result, 'name="conversion_filters[1][values][]"'
  end

  test "hidden_filter_params handles simple arrays" do
    @filter_params = {
      channels: ["paid_search", "organic"]
    }

    result = hidden_filter_params

    assert_includes result, 'name="channels[]"'
    assert_includes result, 'value="paid_search"'
    assert_includes result, 'value="organic"'
  end

  test "hidden_filter_params handles simple values" do
    @filter_params = {
      date_range: "7d",
      metric: "conversions"
    }

    result = hidden_filter_params

    assert_includes result, 'name="date_range"'
    assert_includes result, 'value="7d"'
    assert_includes result, 'name="metric"'
    assert_includes result, 'value="conversions"'
  end

  test "hidden_filter_params excludes specified keys" do
    @filter_params = {
      date_range: "7d",
      breakdown_dimension: "conversion_type"
    }

    result = hidden_filter_params(except: [:breakdown_dimension])

    assert_includes result, 'name="date_range"'
    refute_includes result, 'breakdown_dimension'
  end

  # hidden_params_for tests
  test "hidden_params_for generates hidden fields from a hash" do
    result = hidden_params_for(date_range: "7d", metric: "revenue")

    assert_includes result, 'name="date_range"'
    assert_includes result, 'value="7d"'
    assert_includes result, 'name="metric"'
    assert_includes result, 'value="revenue"'
  end

  test "hidden_params_for handles nested hashes" do
    result = hidden_params_for(
      "conversion_filters" => {
        "0" => { "field" => "location", "operator" => "equals", "values" => ["Sydney"] }
      }
    )

    assert_includes result, 'name="conversion_filters[0][field]"'
    assert_includes result, 'value="location"'
    assert_includes result, 'name="conversion_filters[0][values][]"'
    assert_includes result, 'value="Sydney"'
  end

  test "hidden_params_for handles arrays" do
    result = hidden_params_for("channels" => ["paid_search", "email"])

    assert_includes result, 'name="channels[]"'
    assert_includes result, 'value="paid_search"'
    assert_includes result, 'value="email"'
  end

  test "hidden_params_for returns empty string for empty hash" do
    result = hidden_params_for({})

    assert_equal "", result
  end
end
