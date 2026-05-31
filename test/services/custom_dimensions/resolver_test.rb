# frozen_string_literal: true

require "test_helper"

# Pure resolver: given active dimensions + a connection's metadata baseline,
# produce { key => value } for one campaign row. No DB — dimensions are built
# in memory. See lib/specs/custom_dimensions_spec.md Phase 3.
class CustomDimensions::ResolverTest < ActiveSupport::TestCase
  test "by-campaign dimension returns the first matching rule's output" do
    dim = build_dimension(key: "location", mode: "campaign", rules: [
      { field: "campaign_name", op: "contains", value: "austin", out: "Austin", position: 1 },
      { field: "campaign_name", op: "contains", value: "a", out: "Wrong", position: 2 }
    ])

    assert_equal({ "location" => "Austin" }, resolver([ dim ]).call(campaign_name: "AcmeOutdoors | Austin | Search"))
  end

  test "first match wins by position regardless of insertion order" do
    dim = build_dimension(key: "location", mode: "campaign", rules: [
      { field: "campaign_name", op: "contains", value: "a", out: "Broad", position: 2 },
      { field: "campaign_name", op: "contains", value: "austin", out: "Austin", position: 1 }
    ])

    assert_equal "Austin", resolver([ dim ]).call(campaign_name: "Austin")["location"]
  end

  test "campaign_id match field maps to platform_campaign_id" do
    dim = build_dimension(key: "location", mode: "campaign", rules: [
      { field: "campaign_id", op: "equals", value: "123", out: "Tagged", position: 1 }
    ])

    assert_equal "Tagged", resolver([ dim ]).call(platform_campaign_id: "123")["location"]
  end

  test "no rule match falls back to the connection value, then the default" do
    dim = build_dimension(key: "location", mode: "campaign", default: "Other", rules: [
      { field: "campaign_name", op: "contains", value: "zzz", out: "Z", position: 1 }
    ])

    assert_equal "HQ", resolver([ dim ], metadata: { "location" => "HQ" }).call(campaign_name: "nope")["location"]
    assert_equal "Other", resolver([ dim ]).call(campaign_name: "nope")["location"]
  end

  test "by-account dimension returns the connection value, else the default" do
    dim = build_dimension(key: "region", mode: "account", default: "Other")

    assert_equal "West Coast", resolver([ dim ], metadata: { "region" => "West Coast" }).call(campaign_name: "x")["region"]
    assert_equal "Other", resolver([ dim ]).call(campaign_name: "x")["region"]
  end

  test "resolves multiple dimensions into one hash" do
    loc = build_dimension(key: "location", mode: "campaign", rules: [
      { field: "campaign_name", op: "contains", value: "austin", out: "Austin", position: 1 }
    ])
    region = build_dimension(key: "region", mode: "account", default: "Other")

    out = resolver([ loc, region ], metadata: { "region" => "South" }).call(campaign_name: "Austin")

    assert_equal({ "location" => "Austin", "region" => "South" }, out)
  end

  test "regex operator runs through the shared operator engine" do
    dim = build_dimension(key: "location", mode: "campaign", rules: [
      { field: "campaign_name", op: "regex", value: "den|denver", out: "Denver", position: 1 }
    ])

    assert_equal "Denver", resolver([ dim ]).call(campaign_name: "DEN-01")["location"]
  end

  test "no dimensions yields an empty hash" do
    assert_equal({}, resolver([]).call(campaign_name: "x"))
  end

  private

  def resolver(dimensions, metadata: {})
    CustomDimensions::Resolver.new(dimensions: dimensions, connection_metadata: metadata)
  end

  def build_dimension(key:, mode:, default: "Other", rules: [])
    dim = CustomDimension.new(key: key, name: key.capitalize, mapping_mode: mode, default_value: default)
    rules.each do |r|
      dim.dimension_rules.build(match_field: r[:field], operator: r[:op], value: r[:value], output_value: r[:out], position: r[:position])
    end
    dim
  end
end
