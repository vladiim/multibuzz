# frozen_string_literal: true

require "test_helper"

class AdPlatforms::MetadataLinkCheckTest < ActiveSupport::TestCase
  test "returns no_metadata when connection has no metadata" do
    connection.update!(metadata: {})

    assert_equal({ state: :no_metadata }, AdPlatforms::MetadataLinkCheck.new(connection).call)
  end

  test "returns linked state when matching conversions exist" do
    connection.update!(metadata: { "location" => "Eumundi-Noosa" })
    create_conversion(properties: { "location" => "Eumundi-Noosa" })
    create_conversion(properties: { "location" => "Sydney" })

    assert_equal :linked, AdPlatforms::MetadataLinkCheck.new(connection).call[:state]
  end

  test "linked result echoes the count, key, and value" do
    connection.update!(metadata: { "location" => "Eumundi-Noosa" })
    create_conversion(properties: { "location" => "Eumundi-Noosa" })
    create_conversion(properties: { "location" => "Eumundi-Noosa" })

    result = AdPlatforms::MetadataLinkCheck.new(connection).call

    assert_equal({ count: 2, key: "location", value: "Eumundi-Noosa" }, result.slice(:count, :key, :value))
  end

  test "returns unlinked with no hint when no matches at all" do
    connection.update!(metadata: { "location" => "Eumundi-Noosa" })
    create_conversion(properties: { "location" => "Sydney" })

    result = AdPlatforms::MetadataLinkCheck.new(connection).call

    assert_equal :unlinked, result[:state]
    assert_nil result[:hint]
  end

  test "returns unlinked with case-insensitive hint when near-miss exists" do
    connection.update!(metadata: { "location" => "Eumundi-Noosa" })
    3.times { create_conversion(properties: { "location" => "eumundi-noosa" }) }

    result = AdPlatforms::MetadataLinkCheck.new(connection).call

    assert_equal :unlinked, result[:state]
    assert_equal "eumundi-noosa", result.dig(:hint, :suggested_value)
    assert_equal 3, result.dig(:hint, :count)
  end

  test "ignores conversions older than 90 days" do
    connection.update!(metadata: { "location" => "Sydney" })
    create_conversion(properties: { "location" => "Sydney" }, converted_at: 100.days.ago)

    result = AdPlatforms::MetadataLinkCheck.new(connection).call

    assert_equal :unlinked, result[:state]
  end

  test "scopes to the connection's account" do
    connection.update!(metadata: { "location" => "Sydney" })
    create_conversion(account: accounts(:two), properties: { "location" => "Sydney" })

    result = AdPlatforms::MetadataLinkCheck.new(connection).call

    assert_equal :unlinked, result[:state]
  end

  private

  def connection = @connection ||= ad_platform_connections(:google_ads)

  def create_conversion(account: accounts(:one), properties:, converted_at: 1.day.ago)
    Conversion.create!(
      account: account,
      visitor: visitors(:one),
      conversion_type: "purchase",
      converted_at: converted_at,
      properties: properties,
      journey_session_ids: []
    )
  end
end
