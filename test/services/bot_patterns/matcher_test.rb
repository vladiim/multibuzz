# frozen_string_literal: true

require "test_helper"

class BotPatterns::MatcherTest < ActiveSupport::TestCase
  GOOGLEBOT_UA = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
  AHREFSBOT_UA = "Mozilla/5.0 (compatible; AhrefsBot/7.0; +http://ahrefs.com/robot/)"
  GPTBOT_UA = "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.0; +https://openai.com/gptbot)"
  CHROME_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  SAFARI_MOBILE_UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

  setup do
    BotPatterns::Matcher.reset!
    load_test_patterns
  end

  teardown do
    BotPatterns::Matcher.reset!
  end

  test "detects Googlebot" do
    assert BotPatterns::Matcher.bot?(GOOGLEBOT_UA)
  end

  test "detects AhrefsBot" do
    assert BotPatterns::Matcher.bot?(AHREFSBOT_UA)
  end

  test "detects GPTBot" do
    assert BotPatterns::Matcher.bot?(GPTBOT_UA)
  end

  test "passes Chrome desktop" do
    assert_not BotPatterns::Matcher.bot?(CHROME_UA)
  end

  test "passes Safari mobile" do
    assert_not BotPatterns::Matcher.bot?(SAFARI_MOBILE_UA)
  end

  test "returns false for nil UA" do
    assert_not BotPatterns::Matcher.bot?(nil)
  end

  test "returns false for empty string UA" do
    assert_not BotPatterns::Matcher.bot?("")
  end

  test "returns false when no patterns loaded" do
    BotPatterns::Matcher.reset!

    assert_not BotPatterns::Matcher.bot?(GOOGLEBOT_UA)
  end

  test "bot_name returns matching pattern name" do
    assert_equal "Googlebot", BotPatterns::Matcher.bot_name(GOOGLEBOT_UA)
  end

  test "bot_name returns nil for real browser" do
    assert_nil BotPatterns::Matcher.bot_name(CHROME_UA)
  end

  private

  def load_test_patterns
    patterns = [
      { pattern: "Googlebot", name: "Googlebot" },
      { pattern: "AhrefsBot", name: "AhrefsBot" },
      { pattern: "GPTBot", name: "GPTBot" }
    ]
    BotPatterns::Matcher.load!(patterns)
  end
end
