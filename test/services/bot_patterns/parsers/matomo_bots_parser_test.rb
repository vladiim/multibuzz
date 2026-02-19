# frozen_string_literal: true

require "test_helper"

class BotPatterns::Parsers::MatomoBotsParserTest < ActiveSupport::TestCase
  test "parses regex and name from YAML" do
    yaml = <<~YAML
      - regex: 'Googlebot'
        name: 'Googlebot'
        category: 'Search bot'
        url: 'https://developers.google.com/search/docs/'
        producer:
          name: 'Google Inc.'
          url: 'https://www.google.com/'
      - regex: 'AhrefsBot'
        name: 'Ahrefs Bot'
        category: 'Crawler'
    YAML

    results = parser(yaml).call

    assert_equal 2, results.size
    assert_equal "Googlebot", results[0][:pattern]
    assert_equal "Googlebot", results[0][:name]
    assert_equal "AhrefsBot", results[1][:pattern]
    assert_equal "Ahrefs Bot", results[1][:name]
  end

  test "skips entries without regex" do
    yaml = <<~YAML
      - regex: 'Googlebot'
        name: 'Googlebot'
      - name: 'No Regex Bot'
    YAML

    results = parser(yaml).call

    assert_equal 1, results.size
  end

  test "uses regex as name when name missing" do
    yaml = <<~YAML
      - regex: 'SomeBot'
    YAML

    results = parser(yaml).call

    assert_equal "SomeBot", results.first[:name]
  end

  test "returns empty array for empty YAML" do
    assert_equal [], parser("").call
  end

  test "returns empty array for nil content" do
    assert_equal [], parser(nil).call
  end

  test "returns empty array for malformed YAML" do
    assert_equal [], parser("{{bad yaml").call
  end

  private

  def parser(content)
    BotPatterns::Parsers::MatomoBotsParser.new(content)
  end
end
