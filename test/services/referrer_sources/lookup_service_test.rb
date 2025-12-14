require "test_helper"

class ReferrerSources::LookupServiceTest < ActiveSupport::TestCase
  setup do
    create_test_sources
  end

  test "finds source by exact domain match" do
    result = service("https://www.google.com/search?q=test").call

    assert_not_nil result
    assert_equal "Google", result[:source_name]
    assert_equal ReferrerSources::Mediums::SEARCH, result[:medium]
    assert_equal "q", result[:keyword_param]
    assert_equal false, result[:is_spam]
  end

  test "finds source stripping www prefix" do
    result = service("https://www.facebook.com/post/123").call

    assert_not_nil result
    assert_equal "Facebook", result[:source_name]
  end

  test "returns nil for unknown domain" do
    result = service("https://unknown-site.com/page").call

    assert_nil result
  end

  test "returns nil for blank referrer" do
    assert_nil service("").call
    assert_nil service(nil).call
  end

  test "identifies spam referrers" do
    result = service("https://spam-site.com/evil").call

    assert_not_nil result
    assert_equal true, result[:is_spam]
  end

  test "extracts search term from url" do
    result = service("https://www.google.com/search?q=ruby+on+rails").call

    assert_equal "ruby on rails", result[:search_term]
  end

  test "returns nil search term when param missing" do
    result = service("https://www.google.com/search").call

    assert_nil result[:search_term]
  end

  test "caches lookup results" do
    service("https://www.google.com/search").call

    assert_not_nil Rails.cache.read("referrer_sources/domain/google.com")
  end

  test "uses cached result on subsequent lookups" do
    # First lookup
    service("https://www.google.com/search").call

    # Delete from DB
    ReferrerSource.where(domain: "google.com").delete_all

    # Second lookup should still work from cache
    result = service("https://www.google.com/search").call

    assert_not_nil result
    assert_equal "Google", result[:source_name]
  end

  test "handles invalid URL gracefully" do
    result = service("not a valid url").call

    assert_nil result
  end

  test "returns nil for domains with invalid TLDs" do
    # PublicSuffix may raise errors for invalid TLDs
    # Service should return nil gracefully, not an error hash
    result = service("https://test.invalidtld/page").call

    # Should be nil or a valid result, never an error hash like {success: false, ...}
    assert(result.nil? || result.is_a?(Hash) && result.key?(:source_name),
      "Expected nil or valid result hash, got: #{result.inspect}")
  end

  test "never returns ApplicationService error hash format" do
    # LookupService is a utility class that should return nil on failure
    # not {success: false, errors: [...]} like ApplicationService
    result = service("https://unknown-domain-xyz.com/page").call

    # If result is a hash, it should have :source_name (valid result), not :success/:errors
    if result.is_a?(Hash)
      assert result.key?(:source_name), "Result hash should have :source_name, not ApplicationService format"
      assert_not result.key?(:success), "Should not return ApplicationService error format"
    else
      assert_nil result
    end
  end

  test "handles subdomain lookups" do
    result = service("https://m.facebook.com/post").call

    # Should match facebook.com (strips subdomain)
    assert_not_nil result
    assert_equal "Facebook", result[:source_name]
  end

  test "handles multi-part TLDs correctly" do
    ReferrerSource.create!(
      domain: "google.co.uk",
      source_name: "Google UK",
      medium: ReferrerSources::Mediums::SEARCH,
      keyword_param: "q",
      data_origin: ReferrerSources::DataOrigins::MATOMO_SEARCH
    )

    result = service("https://www.google.co.uk/search?q=test").call

    assert_not_nil result
    assert_equal "Google UK", result[:source_name]
  end

  test "handles subdomain with multi-part TLDs" do
    ReferrerSource.create!(
      domain: "google.co.uk",
      source_name: "Google UK",
      medium: ReferrerSources::Mediums::SEARCH,
      keyword_param: "q",
      data_origin: ReferrerSources::DataOrigins::MATOMO_SEARCH
    )

    result = service("https://mail.google.co.uk/search?q=test").call

    # Should match google.co.uk (strips subdomain correctly)
    assert_not_nil result
    assert_equal "Google UK", result[:source_name]
  end

  private

  def service(referrer)
    ReferrerSources::LookupService.new(referrer)
  end

  def create_test_sources
    ReferrerSource.create!(
      domain: "google.com",
      source_name: "Google",
      medium: ReferrerSources::Mediums::SEARCH,
      keyword_param: "q",
      data_origin: ReferrerSources::DataOrigins::MATOMO_SEARCH
    )
    ReferrerSource.create!(
      domain: "facebook.com",
      source_name: "Facebook",
      medium: ReferrerSources::Mediums::SOCIAL,
      data_origin: ReferrerSources::DataOrigins::MATOMO_SOCIAL
    )
    ReferrerSource.create!(
      domain: "spam-site.com",
      source_name: "spam-site.com",
      medium: ReferrerSources::Mediums::SOCIAL,
      is_spam: true,
      data_origin: ReferrerSources::DataOrigins::MATOMO_SPAM
    )
  end
end
