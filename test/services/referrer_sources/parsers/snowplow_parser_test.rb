require "test_helper"

class ReferrerSources::Parsers::SnowplowParserTest < ActiveSupport::TestCase
  test "parses search engine from json" do
    json_content = {
      "search" => {
        "Google" => {
          "domains" => ["google.com"],
          "parameters" => ["q"]
        }
      }
    }.to_json

    results = parser(json_content).call

    assert_equal 1, results.size
    assert_equal "google.com", results.first[:domain]
    assert_equal "Google", results.first[:source_name]
    assert_equal ReferrerSources::Mediums::SEARCH, results.first[:medium]
    assert_equal "q", results.first[:keyword_param]
    assert_equal false, results.first[:is_spam]
    assert_equal ReferrerSources::DataOrigins::SNOWPLOW, results.first[:data_origin]
  end

  test "parses social network from json" do
    json_content = {
      "social" => {
        "Facebook" => {
          "domains" => ["facebook.com", "fb.com"]
        }
      }
    }.to_json

    results = parser(json_content).call

    assert_equal 2, results.size
    assert results.all? { |r| r[:medium] == ReferrerSources::Mediums::SOCIAL }
    assert results.all? { |r| r[:source_name] == "Facebook" }
  end

  test "parses email provider from json" do
    json_content = {
      "email" => {
        "Gmail" => {
          "domains" => ["mail.google.com"]
        }
      }
    }.to_json

    results = parser(json_content).call

    assert_equal 1, results.size
    assert_equal ReferrerSources::Mediums::EMAIL, results.first[:medium]
  end

  test "parses multiple mediums" do
    json_content = {
      "search" => {
        "Google" => { "domains" => ["google.com"], "parameters" => ["q"] }
      },
      "social" => {
        "Facebook" => { "domains" => ["facebook.com"] }
      },
      "email" => {
        "Gmail" => { "domains" => ["mail.google.com"] }
      }
    }.to_json

    results = parser(json_content).call

    mediums = results.map { |r| r[:medium] }.uniq
    assert_includes mediums, ReferrerSources::Mediums::SEARCH
    assert_includes mediums, ReferrerSources::Mediums::SOCIAL
    assert_includes mediums, ReferrerSources::Mediums::EMAIL
  end

  test "handles unknown medium gracefully" do
    json_content = {
      "unknown" => {
        "Something" => { "domains" => ["something.com"] }
      }
    }.to_json

    results = parser(json_content).call

    # Should skip unknown mediums
    assert_equal 0, results.size
  end

  test "returns empty array for empty json" do
    results = parser("{}").call

    assert_equal [], results
  end

  test "returns empty array for nil content" do
    results = parser(nil).call

    assert_equal [], results
  end

  test "returns empty array for invalid json" do
    results = parser("not valid json").call

    assert_equal [], results
  end

  private

  def parser(json_content)
    ReferrerSources::Parsers::SnowplowParser.new(json_content)
  end
end
