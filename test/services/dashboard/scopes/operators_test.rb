# frozen_string_literal: true

require "test_helper"

# Phase 1 of the Custom Dimensions spec (lib/specs/custom_dimensions_spec.md):
# the operator engine becomes the single source of truth for matching, shared by
# dashboard SQL filters and in-memory custom-dimension resolution.
class Dashboard::Scopes::OperatorsTest < ActiveSupport::TestCase
  Operators = Dashboard::Scopes::Operators

  # --- Scalar dispatcher: Operators.matches?(operator:, candidate:, value:) ---

  test "equals matches case-sensitively (parity with SQL =)" do
    assert matches?("equals", "Portland", "Portland")
    refute matches?("equals", "portland", "Portland")
    refute matches?("equals", "Portland Metro", "Portland")
  end

  test "not_equals is the inverse of equals" do
    assert matches?("not_equals", "Austin", "Portland")
    refute matches?("not_equals", "Portland", "Portland")
  end

  test "contains is a case-insensitive substring (parity with ILIKE)" do
    assert matches?("contains", "AcmeOutdoors | Portland | Search", "portland")
    assert matches?("contains", "PORTLAND", "portland")
    refute matches?("contains", "Austin Search", "portland")
  end

  test "starts_with is case-insensitive prefix" do
    assert matches?("starts_with", "Portland Metro", "portland")
    refute matches?("starts_with", "Metro Portland", "portland")
  end

  test "ends_with is case-insensitive suffix" do
    assert matches?("ends_with", "Search - Portland", "portland")
    refute matches?("ends_with", "Portland - Search", "portland")
  end

  test "regex matches case-insensitively" do
    assert matches?("regex", "Denver Search", "den|denver")
    assert matches?("regex", "DEN-01", "^den")
    refute matches?("regex", "Austin", "den|denver")
  end

  test "regex with an invalid pattern returns false instead of raising" do
    assert_nothing_raised { matches?("regex", "anything", "(") }
    refute matches?("regex", "anything", "(")
  end

  test "nil and blank candidates never match (except where logically true)" do
    refute matches?("contains", nil, "portland")
    refute matches?("starts_with", nil, "portland")
    assert matches?("not_equals", nil, "portland")
  end

  test "non-matchable and unknown operators return false, not raise" do
    refute matches?("greater_than", "5", "3")
    refute matches?("less_than", "1", "3")
    refute matches?("totally_unknown", "a", "a")
  end

  # --- SQL mode unchanged + new operators emit correct SQL ---

  test "starts_with emits an anchored ILIKE on a property" do
    sql = Operators::StartsWith.new(field: "location", values: ["port"], table_name: nil).call(Conversion.all).to_sql
    assert_includes sql, "properties->>'location' ILIKE 'port%'"
  end

  test "ends_with emits a suffix ILIKE on a property" do
    sql = Operators::EndsWith.new(field: "location", values: ["port"], table_name: nil).call(Conversion.all).to_sql
    assert_includes sql, "properties->>'location' ILIKE '%port'"
  end

  test "regex emits a case-insensitive POSIX match on a property" do
    sql = Operators::Regex.new(field: "location", values: ["den|denver"], table_name: nil).call(Conversion.all).to_sql
    assert_includes sql, "properties->>'location' ~* 'den|denver'"
  end

  test "scalar contains agrees with the SQL ILIKE semantics (parity)" do
    # Both are case-insensitive substring matching.
    candidate = "AcmeOutdoors | Portland | Search"
    assert matches?("contains", candidate, "portland")
    sql = Operators::Contains.new(field: "campaign_name", values: ["portland"], table_name: nil).call(Conversion.all).to_sql
    assert_includes sql, "ILIKE '%portland%'"
  end

  private

  def matches?(operator, candidate, value)
    Operators.matches?(operator: operator, candidate: candidate, value: value)
  end
end
