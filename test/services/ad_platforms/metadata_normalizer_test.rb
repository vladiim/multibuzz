# frozen_string_literal: true

require "test_helper"

class AdPlatforms::MetadataNormalizerTest < ActiveSupport::TestCase
  test "lowercases keys and preserves value case" do
    out = AdPlatforms::MetadataNormalizer.call("Location" => "Eumundi-Noosa", "Brand" => "Premium Brand")

    assert_equal({ "location" => "Eumundi-Noosa", "brand" => "Premium Brand" }, out)
  end

  test "strips whitespace from keys and values" do
    out = AdPlatforms::MetadataNormalizer.call("  location  " => "  Sydney  ")

    assert_equal({ "location" => "Sydney" }, out)
  end

  test "drops pairs with blank key" do
    out = AdPlatforms::MetadataNormalizer.call("" => "Sydney", "location" => "Sydney")

    assert_equal({ "location" => "Sydney" }, out)
  end

  test "drops pairs with blank value" do
    out = AdPlatforms::MetadataNormalizer.call("location" => "", "brand" => "Premium")

    assert_equal({ "brand" => "Premium" }, out)
  end

  test "returns empty hash for nil input" do
    assert_equal({}, AdPlatforms::MetadataNormalizer.call(nil))
  end

  test "returns empty hash for non-hash input" do
    assert_equal({}, AdPlatforms::MetadataNormalizer.call("not a hash"))
  end

  test "coerces non-string values to strings" do
    out = AdPlatforms::MetadataNormalizer.call("count" => 42)

    assert_equal({ "count" => "42" }, out)
  end
end
