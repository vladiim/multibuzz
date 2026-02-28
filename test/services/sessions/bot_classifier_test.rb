# frozen_string_literal: true

require "test_helper"

class Sessions::BotClassifierTest < ActiveSupport::TestCase
  GOOGLEBOT_UA = "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
  CHROME_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"

  setup do
    BotPatterns::Matcher.reset!
    BotPatterns::Matcher.load!([
      { pattern: "Googlebot", name: "Googlebot" },
      { pattern: "AhrefsBot", name: "AhrefsBot" }
    ])
  end

  teardown do
    BotPatterns::Matcher.reset!
  end

  test "bot UA returns suspect with known_bot reason" do
    result = classify(user_agent: GOOGLEBOT_UA)

    assert result[:suspect]
    assert_equal "known_bot", result[:suspect_reason]
  end

  test "bot UA with attribution signals still marked suspect" do
    result = classify(
      user_agent: GOOGLEBOT_UA,
      referrer: "https://google.com",
      utm: { source: "google" },
      click_ids: { gclid: "abc123" }
    )

    assert result[:suspect]
    assert_equal "known_bot", result[:suspect_reason]
  end

  test "real UA with attribution signals is qualified" do
    result = classify(
      user_agent: CHROME_UA,
      referrer: "https://google.com",
      utm: { source: "google" }
    )

    assert_not result[:suspect]
    assert_nil result[:suspect_reason]
  end

  test "real UA with no signals is suspect with no_signals reason" do
    result = classify(
      user_agent: CHROME_UA,
      referrer: nil,
      utm: {},
      click_ids: {}
    )

    assert result[:suspect]
    assert_equal "no_signals", result[:suspect_reason]
  end

  test "nil UA with no signals falls back to no_signals" do
    result = classify(
      user_agent: nil,
      referrer: nil,
      utm: {},
      click_ids: {}
    )

    assert result[:suspect]
    assert_equal "no_signals", result[:suspect_reason]
  end

  test "nil UA with signals is qualified" do
    result = classify(
      user_agent: nil,
      referrer: "https://google.com",
      utm: { source: "google" }
    )

    assert_not result[:suspect]
    assert_nil result[:suspect_reason]
  end

  test "empty string UA with no signals falls back to no_signals" do
    result = classify(
      user_agent: "",
      referrer: nil,
      utm: {},
      click_ids: {}
    )

    assert result[:suspect]
    assert_equal "no_signals", result[:suspect_reason]
  end

  # ==========================================
  # Spam Referrer Detection Tests
  # ==========================================

  test "raw IP referrer returns suspect with spam_referrer reason" do
    result = classify(
      user_agent: CHROME_UA,
      referrer: "http://52.62.84.103:80/getcmd"
    )

    assert result[:suspect]
    assert_equal "spam_referrer", result[:suspect_reason]
  end

  test "raw IP referrer without port returns suspect" do
    result = classify(
      user_agent: CHROME_UA,
      referrer: "http://192.168.1.1/path"
    )

    assert result[:suspect]
    assert_equal "spam_referrer", result[:suspect_reason]
  end

  test "known spam domain binance.com returns suspect" do
    result = classify(
      user_agent: CHROME_UA,
      referrer: "https://binance.com"
    )

    assert result[:suspect]
    assert_equal "spam_referrer", result[:suspect_reason]
  end

  test "known spam domain shsupplychain.com returns suspect" do
    result = classify(
      user_agent: CHROME_UA,
      referrer: "https://www.shsupplychain.com/"
    )

    assert result[:suspect]
    assert_equal "spam_referrer", result[:suspect_reason]
  end

  test "known spam domain with subdomain returns suspect" do
    result = classify(
      user_agent: CHROME_UA,
      referrer: "https://sub.binance.com/path"
    )

    assert result[:suspect]
    assert_equal "spam_referrer", result[:suspect_reason]
  end

  test "known bot takes priority over spam referrer" do
    result = classify(
      user_agent: GOOGLEBOT_UA,
      referrer: "https://binance.com"
    )

    assert result[:suspect]
    assert_equal "known_bot", result[:suspect_reason]
  end

  test "legitimate referrer is not flagged as spam" do
    result = classify(
      user_agent: CHROME_UA,
      referrer: "https://google.com/search"
    )

    assert_not result[:suspect]
    assert_nil result[:suspect_reason]
  end

  test "spam referrer with utm signals still flagged as suspect" do
    result = classify(
      user_agent: CHROME_UA,
      referrer: "https://binance.com",
      utm: { source: "binance" },
      click_ids: {}
    )

    assert result[:suspect]
    assert_equal "spam_referrer", result[:suspect_reason]
  end

  private

  def classify(user_agent: nil, referrer: nil, utm: {}, click_ids: {})
    Sessions::BotClassifier.new(
      user_agent: user_agent,
      referrer: referrer,
      utm: utm,
      click_ids: click_ids
    ).call
  end
end
