require "test_helper"

class ReferrerSources::Parsers::MatomoSocialParserTest < ActiveSupport::TestCase
  test "parses social network with single domain" do
    yaml_content = <<~YAML
      Facebook:
        - facebook.com
    YAML

    results = parser(yaml_content).call

    assert_equal 1, results.size
    assert_equal "facebook.com", results.first[:domain]
    assert_equal "Facebook", results.first[:source_name]
    assert_equal ReferrerSources::Mediums::SOCIAL, results.first[:medium]
    assert_nil results.first[:keyword_param]
    assert_equal false, results.first[:is_spam]
    assert_equal ReferrerSources::DataOrigins::MATOMO_SOCIAL, results.first[:data_origin]
  end

  test "parses social network with multiple domains" do
    yaml_content = <<~YAML
      Facebook:
        - facebook.com
        - fb.com
        - m.facebook.com
    YAML

    results = parser(yaml_content).call

    assert_equal 3, results.size
    assert_equal %w[facebook.com fb.com m.facebook.com], results.map { |r| r[:domain] }
    assert results.all? { |r| r[:source_name] == "Facebook" }
  end

  test "parses multiple social networks" do
    yaml_content = <<~YAML
      Facebook:
        - facebook.com
      Twitter:
        - twitter.com
        - t.co
      LinkedIn:
        - linkedin.com
    YAML

    results = parser(yaml_content).call

    assert_equal 4, results.size
    source_names = results.map { |r| r[:source_name] }
    assert_includes source_names, "Facebook"
    assert_includes source_names, "Twitter"
    assert_includes source_names, "LinkedIn"
  end

  test "all results have social medium" do
    yaml_content = <<~YAML
      Facebook:
        - facebook.com
      Twitter:
        - twitter.com
    YAML

    results = parser(yaml_content).call

    assert results.all? { |r| r[:medium] == ReferrerSources::Mediums::SOCIAL }
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
    ReferrerSources::Parsers::MatomoSocialParser.new(yaml_content)
  end
end
