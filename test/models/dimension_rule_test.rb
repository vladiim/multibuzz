# frozen_string_literal: true

require "test_helper"

class DimensionRuleTest < ActiveSupport::TestCase
  test "has a prefixed id with the drul_ prefix" do
    assert_match(/\Adrul_/, rule.tap(&:save!).prefix_id)
  end

  test "belongs to an account and a custom dimension" do
    assert_equal account, rule.account
    assert_equal dimension, rule.custom_dimension
  end

  test "requires value and output_value" do
    blank = dimension.dimension_rules.new(account: account, match_field: "campaign_name", operator: "contains", value: "", output_value: "")

    assert_not blank.valid?
    assert_includes blank.errors[:value], "can't be blank"
    assert_includes blank.errors[:output_value], "can't be blank"
  end

  test "rejects an unknown match field" do
    rule.match_field = "campaign_colour"

    assert_not rule.valid?
    assert_includes rule.errors[:match_field], "is not included in the list"
  end

  test "operator must be one of the shared matchable operators" do
    assert_equal Dashboard::Scopes::Operators::MATCHABLE, DimensionRule::OPERATORS

    rule.operator = "greater_than"
    assert_not rule.valid?
    assert_includes rule.errors[:operator], "is not included in the list"
  end

  test "a regex rule rejects an uncompilable pattern" do
    rule.operator = "regex"
    rule.value = "("

    assert_not rule.valid?
    assert_includes rule.errors[:value], "is not a valid regular expression"
  end

  test "a regex rule accepts a valid pattern" do
    rule.operator = "regex"
    rule.value = "den|denver"

    assert rule.valid?
  end

  test "caps the value length" do
    rule.value = "a" * 501

    assert_not rule.valid?
  end

  test "rules apply only to by-campaign dimensions" do
    by_account = account.custom_dimensions.create!(key: "region", name: "Region", mapping_mode: "account")
    orphan = by_account.dimension_rules.new(account: account, match_field: "campaign_name", operator: "contains", value: "x", output_value: "y")

    assert_not orphan.valid?
    assert_includes orphan.errors[:base], "rules apply to by-campaign dimensions only"
  end

  test "ordered scope sorts by position" do
    dimension.save!
    second = dimension.dimension_rules.create!(account: account, position: 2, match_field: "campaign_name", operator: "contains", value: "b", output_value: "B")
    first = dimension.dimension_rules.create!(account: account, position: 1, match_field: "campaign_name", operator: "contains", value: "a", output_value: "A")

    assert_equal [ first, second ], dimension.dimension_rules.ordered.to_a
  end

  private

  def rule
    @rule ||= dimension.dimension_rules.new(
      account: account, match_field: "campaign_name", operator: "contains", value: "portland", output_value: "Portland"
    )
  end

  def dimension
    @dimension ||= account.custom_dimensions.create!(key: "location", name: "Location", mapping_mode: "campaign")
  end

  def account = @account ||= accounts(:one)
end
