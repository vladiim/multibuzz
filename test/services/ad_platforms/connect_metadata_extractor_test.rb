# frozen_string_literal: true

require "test_helper"

class AdPlatforms::ConnectMetadataExtractorTest < ActiveSupport::TestCase
  test "returns single key-value hash from dropdown selections" do
    out = AdPlatforms::ConnectMetadataExtractor.call(
      ActionController::Parameters.new(metadata_key: "location", metadata_value: "Sydney")
    )

    assert_equal({ "location" => "Sydney" }, out)
  end

  test "prefers typed new key over dropdown" do
    out = AdPlatforms::ConnectMetadataExtractor.call(
      ActionController::Parameters.new(metadata_key: "__new__", metadata_key_new: "Channel", metadata_value: "Search")
    )

    assert_equal({ "Channel" => "Search" }, out)
  end

  test "prefers typed new value over dropdown" do
    out = AdPlatforms::ConnectMetadataExtractor.call(
      ActionController::Parameters.new(metadata_key: "location", metadata_value: "__new__", metadata_value_new: "Brisbane")
    )

    assert_equal({ "location" => "Brisbane" }, out)
  end

  test "returns empty hash when key is blank" do
    out = AdPlatforms::ConnectMetadataExtractor.call(
      ActionController::Parameters.new(metadata_key: "", metadata_value: "Sydney")
    )

    assert_equal({}, out)
  end

  test "returns empty hash when value is blank" do
    out = AdPlatforms::ConnectMetadataExtractor.call(
      ActionController::Parameters.new(metadata_key: "location", metadata_value: "")
    )

    assert_equal({}, out)
  end

  test "returns empty hash when key is sentinel and no new input" do
    out = AdPlatforms::ConnectMetadataExtractor.call(
      ActionController::Parameters.new(metadata_key: "__new__", metadata_value: "Sydney")
    )

    assert_equal({}, out)
  end

  test "returns empty hash for empty params" do
    assert_equal({}, AdPlatforms::ConnectMetadataExtractor.call(ActionController::Parameters.new))
  end
end
