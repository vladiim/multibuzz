# frozen_string_literal: true

require "test_helper"

class ConversionDestinationTest < ActiveSupport::TestCase
  test "has prefixed_id with cdest_ prefix" do
    destination.save!

    assert_match(/\Acdest_/, destination.prefix_id)
  end

  test "belongs to account" do
    assert_equal account, destination.account
  end

  test "belongs to attribution model" do
    assert_equal attribution_model, destination.attribution_model
  end

  test "optionally belongs to ad_platform_connection" do
    assert_nil destination.ad_platform_connection
  end

  test "has many conversion_dispatches" do
    assert_respond_to destination, :conversion_dispatches
  end

  test "rejects blank platform" do
    destination.platform = nil

    assert_not destination.valid?
    assert_includes destination.errors[:platform], "can't be blank"
  end

  test "rejects unknown platform" do
    destination.platform = "tiktok_capi"

    assert_not destination.valid?
    assert_includes destination.errors[:platform], "is not included in the list"
  end

  test "accepts meta_capi and google_ec platforms" do
    %w[meta_capi google_ec].each do |valid_platform|
      destination.platform = valid_platform

      assert_predicate destination, :valid?, "#{valid_platform} should be valid"
    end
  end

  test "rejects unknown revenue_mode" do
    destination.revenue_mode = "exponential"

    assert_not destination.valid?
    assert_includes destination.errors[:revenue_mode], "is not included in the list"
  end

  test "accepts full and scaled revenue_mode" do
    %w[full scaled].each do |valid_mode|
      destination.revenue_mode = valid_mode

      assert_predicate destination, :valid?, "#{valid_mode} should be valid"
    end
  end

  test "rejects negative minimum_credit_threshold" do
    destination.minimum_credit_threshold = -0.1

    assert_not destination.valid?
  end

  test "rejects minimum_credit_threshold above 1.0" do
    destination.minimum_credit_threshold = 1.5

    assert_not destination.valid?
  end

  test "encrypts meta_access_token at rest" do
    destination.meta_access_token = "test_token_secret_value"
    destination.save!

    raw_value = ActiveRecord::Base.connection.select_value(
      "SELECT meta_access_token FROM conversion_destinations WHERE id = #{destination.id}"
    )

    assert_not_equal "test_token_secret_value", raw_value
    assert_equal "test_token_secret_value", destination.reload.meta_access_token
  end

  test "scopes enabled destinations only" do
    enabled = ConversionDestination.create!(
      account: account, attribution_model: attribution_model,
      platform: "meta_capi", name: "Meta", enabled: true
    )
    ConversionDestination.create!(
      account: account, attribution_model: attribution_model,
      platform: "google_ec", name: "Google", enabled: false
    )

    assert_includes ConversionDestination.enabled, enabled
    assert_equal 1, ConversionDestination.enabled.count
  end

  private

  def destination
    @destination ||= ConversionDestination.new(
      account: account,
      attribution_model: attribution_model,
      platform: "meta_capi",
      name: "BSA Meta CAPI",
      enabled: false,
      revenue_mode: "full",
      minimum_credit_threshold: 0.0
    )
  end

  def account
    @account ||= accounts(:one)
  end

  def attribution_model
    @attribution_model ||= attribution_models(:last_touch)
  end
end
