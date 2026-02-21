# frozen_string_literal: true

require "test_helper"

class BotPatterns::Parsers::CrawlerUserAgentsParserTest < ActiveSupport::TestCase
  test "parses pattern and name from JSON" do
    json = <<~JSON
      [
        {"pattern": "Googlebot\\\\/", "url": "http://www.google.com/bot.html", "instances": ["Googlebot/2.1"]},
        {"pattern": "AhrefsBot", "url": "https://ahrefs.com/robot", "instances": ["AhrefsBot/7.0"]}
      ]
    JSON

    results = parser(json).call

    assert_equal 2, results.size
    assert_equal "Googlebot\\/", results[0][:pattern]
    assert_equal "Googlebot\\/", results[0][:name]
    assert_equal "AhrefsBot", results[1][:pattern]
    assert_equal "AhrefsBot", results[1][:name]
  end

  test "skips entries without pattern" do
    json = <<~JSON
      [
        {"pattern": "Googlebot\\\\/"},
        {"url": "http://example.com"}
      ]
    JSON

    results = parser(json).call

    assert_equal 1, results.size
  end

  test "returns empty array for empty JSON array" do
    assert_empty parser("[]").call
  end

  test "returns empty array for nil content" do
    assert_empty parser(nil).call
  end

  test "returns empty array for malformed JSON" do
    assert_empty parser("not json").call
  end

  private

  def parser(content)
    BotPatterns::Parsers::CrawlerUserAgentsParser.new(content)
  end
end
