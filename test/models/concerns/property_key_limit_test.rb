# frozen_string_literal: true

require "test_helper"

class PropertyKeyLimitTest < ActiveSupport::TestCase
  test "truncate keeps the first MAX_PROPERTY_KEYS keys in insertion order" do
    hash = (1..30).each_with_object({}) { |i, h| h["k#{i}"] = i }

    truncated = PropertyKeyLimit.truncate(hash)

    assert_equal 25, truncated.size
    assert_equal (1..25).map { |i| "k#{i}" }, truncated.keys
  end

  test "truncate is a no-op when input is at or below the cap" do
    hash = { "a" => 1, "b" => 2 }

    assert_equal hash, PropertyKeyLimit.truncate(hash)
  end

  test "truncate preserves all reserved keys without counting them" do
    custom_25 = (1..25).each_with_object({}) { |i, h| h["k#{i}"] = i }
    hash = custom_25.merge("url" => "https://example.com", "referrer" => "https://google.com")

    truncated = PropertyKeyLimit.truncate(hash, reserved: %w[url referrer])

    assert_equal 27, truncated.size
    assert_equal "https://example.com", truncated["url"]
  end

  test "truncate drops only custom keys when both reserved and custom overflow" do
    custom_30 = (1..30).each_with_object({}) { |i, h| h["k#{i}"] = i }
    hash = custom_30.merge("url" => "https://example.com")

    truncated = PropertyKeyLimit.truncate(hash, reserved: %w[url referrer])

    assert_equal "https://example.com", truncated["url"]
    custom_keys = truncated.keys - %w[url]

    assert_equal 25, custom_keys.size
  end

  test "truncate returns input unchanged when not a hash" do
    assert_nil PropertyKeyLimit.truncate(nil)
    assert_equal "string", PropertyKeyLimit.truncate("string")
  end

  test "overflow returns the count of dropped custom keys" do
    hash = (1..30).each_with_object({}) { |i, h| h["k#{i}"] = i }

    assert_equal 5, PropertyKeyLimit.overflow(hash)
  end

  test "overflow is zero when input is at or below the cap" do
    assert_equal 0, PropertyKeyLimit.overflow({ "a" => 1, "b" => 2 })
    assert_equal 0, PropertyKeyLimit.overflow((1..25).each_with_object({}) { |i, h| h["k#{i}"] = i })
  end

  test "overflow excludes reserved keys from the count" do
    custom_25 = (1..25).each_with_object({}) { |i, h| h["k#{i}"] = i }
    hash = custom_25.merge("url" => "https://example.com")

    assert_equal 0, PropertyKeyLimit.overflow(hash, reserved: %w[url referrer])
  end

  test "overflow returns zero for non-hash input" do
    assert_equal 0, PropertyKeyLimit.overflow(nil)
    assert_equal 0, PropertyKeyLimit.overflow("string")
  end

  test "truncated? returns true only when overflow is positive" do
    over = (1..30).each_with_object({}) { |i, h| h["k#{i}"] = i }
    under = { "a" => 1 }

    assert PropertyKeyLimit.truncated?(over)
    assert_not PropertyKeyLimit.truncated?(under)
  end
end
