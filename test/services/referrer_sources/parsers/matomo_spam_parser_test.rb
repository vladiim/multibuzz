# frozen_string_literal: true

require "test_helper"

class ReferrerSources::Parsers::MatomoSpamParserTest < ActiveSupport::TestCase
  test "parses single spam domain" do
    content = "spam-site.com"

    results = parser(content).call

    assert_equal 1, results.size
    assert_equal "spam-site.com", results.first[:domain]
    assert_equal "spam-site.com", results.first[:source_name]
    assert_equal ReferrerSources::Mediums::SOCIAL, results.first[:medium]
    assert_nil results.first[:keyword_param]
    assert results.first[:is_spam]
    assert_equal ReferrerSources::DataOrigins::MATOMO_SPAM, results.first[:data_origin]
  end

  test "parses multiple spam domains" do
    content = <<~TXT
      spam-site-1.com
      spam-site-2.com
      spam-site-3.com
    TXT

    results = parser(content).call

    assert_equal 3, results.size
    assert_equal %w[spam-site-1.com spam-site-2.com spam-site-3.com], results.map { |r| r[:domain] }
  end

  test "all results marked as spam" do
    content = <<~TXT
      spam-site-1.com
      spam-site-2.com
    TXT

    results = parser(content).call

    assert results.all? { |r| r[:is_spam] == true }
  end

  test "ignores blank lines" do
    content = <<~TXT
      spam-site-1.com

      spam-site-2.com

    TXT

    results = parser(content).call

    assert_equal 2, results.size
  end

  test "ignores comment lines" do
    content = <<~TXT
      # This is a comment
      spam-site-1.com
      # Another comment
      spam-site-2.com
    TXT

    results = parser(content).call

    assert_equal 2, results.size
    assert results.none? { |r| r[:domain].start_with?("#") }
  end

  test "strips whitespace from domains" do
    content = "  spam-site.com  "

    results = parser(content).call

    assert_equal "spam-site.com", results.first[:domain]
  end

  test "returns empty array for empty content" do
    results = parser("").call

    assert_empty results
  end

  test "returns empty array for nil content" do
    results = parser(nil).call

    assert_empty results
  end

  private

  def parser(content)
    ReferrerSources::Parsers::MatomoSpamParser.new(content)
  end
end
