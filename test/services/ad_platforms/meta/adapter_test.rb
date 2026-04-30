# frozen_string_literal: true

require "test_helper"

class AdPlatforms::Meta::AdapterTest < ActiveSupport::TestCase
  test "inherits from BaseAdapter" do
    assert_kind_of AdPlatforms::BaseAdapter, adapter
  end

  test "validate_connection returns success when token is fresh" do
    connection.update!(token_expires_at: 30.days.from_now)

    assert adapter.validate_connection[:success]
  end

  test "Registry resolves meta_ads to this adapter" do
    resolved = AdPlatforms::Registry.adapter_for(connection)

    assert_kind_of AdPlatforms::Meta::Adapter, resolved
  end

  private

  def adapter = @adapter ||= AdPlatforms::Meta::Adapter.new(connection)
  def connection = @connection ||= ad_platform_connections(:meta_ads)
end
