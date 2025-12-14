require "test_helper"

class Text::LevenshteinMatcherTest < ActiveSupport::TestCase
  # === Distance Calculations ===

  test "returns 0 for identical strings" do
    assert_equal 0, distance("facebook", "facebook")
  end

  test "returns string length for empty comparison" do
    assert_equal 8, distance("facebook", "")
    assert_equal 8, distance("", "facebook")
  end

  test "calculates single character difference" do
    assert_equal 1, distance("cat", "bat")   # substitution
    assert_equal 1, distance("cat", "cats")  # insertion
    assert_equal 1, distance("cats", "cat")  # deletion
  end

  test "calculates multiple character differences" do
    assert_equal 2, distance("facbok", "facebook")  # missing e, o→b
    assert_equal 3, distance("facbk", "facebook")
  end

  # === Matching ===

  test "finds exact match within candidates" do
    assert_equal "facebook", matcher.find_match("facebook")
  end

  test "finds close match within threshold" do
    assert_equal "facebook", matcher.find_match("facebok")   # distance 1
    assert_equal "instagram", matcher.find_match("instagam") # distance 1
  end

  test "returns nil when no match within threshold" do
    assert_nil matcher.find_match("xyz")
    assert_nil matcher.find_match("facbk")  # distance 3
  end

  test "within_threshold returns boolean" do
    assert matcher.within_threshold?("facebook", "facebok")
    refute matcher.within_threshold?("facebook", "xyz")
  end

  private

  def matcher
    @matcher ||= Text::LevenshteinMatcher.new(candidates)
  end

  def candidates
    %w[facebook instagram twitter linkedin]
  end

  def distance(s1, s2)
    Text::LevenshteinMatcher.distance(s1, s2)
  end
end
