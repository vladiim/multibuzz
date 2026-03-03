# frozen_string_literal: true

require "test_helper"

class AdPlatforms::BaseAdapterTest < ActiveSupport::TestCase
  test "fetch_spend raises NotImplementedError" do
    assert_raises(NotImplementedError) do
      adapter.fetch_spend(date_range: Date.current..Date.current)
    end
  end

  test "refresh_token! raises NotImplementedError" do
    assert_raises(NotImplementedError) do
      adapter.refresh_token!
    end
  end

  test "validate_connection raises NotImplementedError" do
    assert_raises(NotImplementedError) do
      adapter.validate_connection
    end
  end

  test "Registry.adapter_for returns Google::Adapter for google_ads connection" do
    result = AdPlatforms::Registry.adapter_for(connection)

    assert_instance_of AdPlatforms::Google::Adapter, result
  end

  test "Registry.adapter_for raises for unsupported platform" do
    connection.platform = :meta_ads

    assert_raises(ArgumentError) do
      AdPlatforms::Registry.adapter_for(connection)
    end
  end

  private

  def adapter = @adapter ||= AdPlatforms::BaseAdapter.new(connection)
  def connection = @connection ||= ad_platform_connections(:google_ads)
end
