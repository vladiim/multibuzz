# frozen_string_literal: true

require "test_helper"

class BotPatterns::SyncServiceTest < ActiveSupport::TestCase
  CRAWLER_JSON = <<~JSON.freeze
    [
      {"pattern": "Googlebot\\\\/", "instances": ["Googlebot/2.1"]},
      {"pattern": "Bingbot", "instances": ["Bingbot/2.0"]}
    ]
  JSON

  MATOMO_YAML = <<~YAML.freeze
    - regex: 'AhrefsBot'
      name: 'Ahrefs Bot'
    - regex: 'GPTBot'
      name: 'GPTBot'
  YAML

  setup do
    BotPatterns::Matcher.reset!
  end

  teardown do
    BotPatterns::Matcher.reset!
  end

  test "parses and loads patterns from both sources" do
    result = sync(crawler: CRAWLER_JSON, matomo: MATOMO_YAML)

    assert result[:success]
    assert_equal 4, result[:pattern_count]
    assert BotPatterns::Matcher.bot?("Googlebot/2.1")
    assert BotPatterns::Matcher.bot?("AhrefsBot/7.0")
  end

  test "deduplicates patterns across sources" do
    crawler = '[{"pattern": "Googlebot\\\\/"},{"pattern": "AhrefsBot"}]'
    matomo = "- regex: 'AhrefsBot'\n  name: 'Ahrefs Bot'"

    result = sync(crawler: crawler, matomo: matomo)

    assert result[:success]
    assert_equal 2, result[:pattern_count]
  end

  test "handles crawler fetch failure gracefully" do
    result = sync(crawler: nil, matomo: MATOMO_YAML)

    assert result[:success]
    assert_equal 2, result[:pattern_count]
    assert BotPatterns::Matcher.bot?("AhrefsBot/7.0")
  end

  test "handles matomo fetch failure gracefully" do
    result = sync(crawler: CRAWLER_JSON, matomo: nil)

    assert result[:success]
    assert_equal 2, result[:pattern_count]
    assert BotPatterns::Matcher.bot?("Googlebot/2.1")
  end

  test "returns error when all sources fail" do
    result = sync(crawler: nil, matomo: nil)

    assert_not result[:success]
  end

  test "writes patterns to cache" do
    sync(crawler: CRAWLER_JSON, matomo: MATOMO_YAML)

    cached = Rails.cache.read(BotPatterns::Sources::CACHE_KEY)
    assert_equal 4, cached.size
  end

  private

  def sync(crawler:, matomo:)
    BotPatterns::SyncService.new(
      fetched_content: {
        BotPatterns::Sources::CRAWLER_USER_AGENTS => crawler,
        BotPatterns::Sources::MATOMO_BOTS => matomo
      }
    ).call
  end
end
