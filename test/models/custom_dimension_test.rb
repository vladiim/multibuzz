# frozen_string_literal: true

require "test_helper"

class CustomDimensionTest < ActiveSupport::TestCase
  test "has a prefixed id with the cdim_ prefix" do
    assert_match(/\Acdim_/, dimension.tap(&:save!).prefix_id)
  end

  test "belongs to an account and has many ordered rules" do
    assert_equal account, dimension.account
    assert_respond_to dimension, :dimension_rules
  end

  test "normalises the key to lowercase and strips it before validation" do
    dimension.key = "  Location  "
    dimension.valid?

    assert_equal "location", dimension.key
  end

  test "requires key, name, and default_value" do
    blank = account.custom_dimensions.new(key: "", name: "", default_value: "")

    assert_not blank.valid?
    assert_includes blank.errors[:key], "can't be blank"
    assert_includes blank.errors[:name], "can't be blank"
    assert_includes blank.errors[:default_value], "can't be blank"
  end

  test "default_value falls back to Other" do
    assert_equal "Other", account.custom_dimensions.create!(key: "location", name: "Location").default_value
  end

  test "defaults to campaign mapping mode" do
    assert_equal "campaign", account.custom_dimensions.create!(key: "location", name: "Location").mapping_mode
  end

  test "rejects an unknown mapping mode" do
    dimension.mapping_mode = "per_visitor"

    assert_not dimension.valid?
    assert_includes dimension.errors[:mapping_mode], "is not included in the list"
  end

  test "key is unique per account but free across accounts" do
    account.custom_dimensions.create!(key: "location", name: "Location")
    dupe = account.custom_dimensions.new(key: "location", name: "Location 2")
    assert_not dupe.valid?

    other = other_account.custom_dimensions.new(key: "location", name: "Location")
    assert other.valid?
  end

  test "a user dimension cannot claim a built-in key" do
    dimension.key = CustomDimension::CHANNEL

    assert_not dimension.valid?
    assert_includes dimension.errors[:key], "is reserved"
  end

  test "the built-in channel dimension may use the channel key" do
    channel = account.custom_dimensions.new(key: CustomDimension::CHANNEL, name: "Channel", built_in: CustomDimension::CHANNEL)

    assert channel.valid?
  end

  test "by_account and by_campaign scopes and predicates" do
    by_acct = account.custom_dimensions.create!(key: "region", name: "Region", mapping_mode: "account")
    by_camp = account.custom_dimensions.create!(key: "location", name: "Location", mapping_mode: "campaign")

    assert_includes account.custom_dimensions.by_account, by_acct
    assert_includes account.custom_dimensions.by_campaign, by_camp
    assert by_acct.by_account?
    assert by_camp.by_campaign?
  end

  test "for_platform returns all-platform dimensions plus the given platform" do
    everywhere = account.custom_dimensions.create!(key: "brand", name: "Brand", platform: nil)
    google = account.custom_dimensions.create!(key: "location", name: "Location", platform: :google_ads)
    meta = account.custom_dimensions.create!(key: "region", name: "Region", platform: :meta_ads)

    scoped = account.custom_dimensions.for_platform(:google_ads)

    assert_includes scoped, everywhere
    assert_includes scoped, google
    assert_not_includes scoped, meta
  end

  test "active scope excludes inactive dimensions" do
    on = account.custom_dimensions.create!(key: "location", name: "Location", is_active: true)
    off = account.custom_dimensions.create!(key: "region", name: "Region", is_active: false)

    assert_includes account.custom_dimensions.active, on
    assert_not_includes account.custom_dimensions.active, off
  end

  private

  def dimension
    @dimension ||= account.custom_dimensions.new(key: "location", name: "Location")
  end

  def account = @account ||= accounts(:one)
  def other_account = @other_account ||= accounts(:two)
end
