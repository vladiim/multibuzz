require "test_helper"

class ReferrerSources::Parsers::MatomoSearchParserTest < ActiveSupport::TestCase
  test "parses search engine with single domain" do
    yaml_content = <<~YAML
      Google:
        urls:
          - google.com
        params:
          - q
    YAML

    results = parser(yaml_content).call

    assert_equal 1, results.size
    assert_equal "google.com", results.first[:domain]
    assert_equal "Google", results.first[:source_name]
    assert_equal ReferrerSources::Mediums::SEARCH, results.first[:medium]
    assert_equal "q", results.first[:keyword_param]
    assert_equal false, results.first[:is_spam]
    assert_equal ReferrerSources::DataOrigins::MATOMO_SEARCH, results.first[:data_origin]
  end

  test "parses search engine with multiple domains" do
    yaml_content = <<~YAML
      Google:
        urls:
          - google.com
          - google.co.uk
          - google.de
        params:
          - q
    YAML

    results = parser(yaml_content).call

    assert_equal 3, results.size
    assert_equal %w[google.com google.co.uk google.de], results.map { |r| r[:domain] }
    assert results.all? { |r| r[:source_name] == "Google" }
  end

  test "parses search engine with multiple params uses first" do
    yaml_content = <<~YAML
      Yahoo:
        urls:
          - yahoo.com
        params:
          - p
          - q
    YAML

    results = parser(yaml_content).call

    assert_equal "p", results.first[:keyword_param]
  end

  test "parses multiple search engines" do
    yaml_content = <<~YAML
      Google:
        urls:
          - google.com
        params:
          - q
      Bing:
        urls:
          - bing.com
        params:
          - q
    YAML

    results = parser(yaml_content).call

    assert_equal 2, results.size
    assert_equal %w[google.com bing.com], results.map { |r| r[:domain] }
  end

  test "expands wildcard domains" do
    yaml_content = <<~YAML
      Google:
        urls:
          - google.{}
        params:
          - q
    YAML

    results = parser(yaml_content).call

    # Should expand to common TLDs
    domains = results.map { |r| r[:domain] }
    assert_includes domains, "google.com"
    assert_includes domains, "google.co.uk"
    assert_includes domains, "google.de"
    assert_includes domains, "google.fr"
  end

  test "handles missing params gracefully" do
    yaml_content = <<~YAML
      SomeEngine:
        urls:
          - someengine.com
    YAML

    results = parser(yaml_content).call

    assert_equal 1, results.size
    assert_nil results.first[:keyword_param]
  end

  test "returns empty array for empty yaml" do
    results = parser("").call

    assert_equal [], results
  end

  test "returns empty array for nil content" do
    results = parser(nil).call

    assert_equal [], results
  end

  private

  def parser(yaml_content)
    ReferrerSources::Parsers::MatomoSearchParser.new(yaml_content)
  end
end
