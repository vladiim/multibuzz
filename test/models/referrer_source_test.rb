require "test_helper"

class ReferrerSourceTest < ActiveSupport::TestCase
  # ==========================================
  # Validation tests
  # ==========================================

  test "valid with all required attributes" do
    assert referrer_source.valid?
  end

  test "invalid without domain" do
    referrer_source.domain = nil
    assert_not referrer_source.valid?
    assert_includes referrer_source.errors[:domain], "can't be blank"
  end

  test "invalid without source_name" do
    referrer_source.source_name = nil
    assert_not referrer_source.valid?
    assert_includes referrer_source.errors[:source_name], "can't be blank"
  end

  test "invalid without medium" do
    referrer_source.medium = nil
    assert_not referrer_source.valid?
    assert_includes referrer_source.errors[:medium], "can't be blank"
  end

  test "invalid without data_origin" do
    referrer_source.data_origin = nil
    assert_not referrer_source.valid?
    assert_includes referrer_source.errors[:data_origin], "can't be blank"
  end

  test "invalid with duplicate domain" do
    referrer_source.save!
    duplicate = ReferrerSource.new(
      domain: referrer_source.domain,
      source_name: "Other",
      medium: ReferrerSources::Mediums::SOCIAL,
      data_origin: ReferrerSources::DataOrigins::CUSTOM
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:domain], "has already been taken"
  end

  test "invalid with medium not in allowed list" do
    referrer_source.medium = "invalid_medium"
    assert_not referrer_source.valid?
    assert_includes referrer_source.errors[:medium], "is not included in the list"
  end

  test "invalid with data_origin not in allowed list" do
    referrer_source.data_origin = "invalid_origin"
    assert_not referrer_source.valid?
    assert_includes referrer_source.errors[:data_origin], "is not included in the list"
  end

  # ==========================================
  # Constants tests
  # ==========================================

  test "mediums constant contains all valid values" do
    expected = %w[search social email video shopping news ai]
    assert_equal expected, ReferrerSources::Mediums::ALL
  end

  test "data_origins constant contains all valid values" do
    expected = %w[matomo_search matomo_social matomo_spam snowplow custom]
    assert_equal expected, ReferrerSources::DataOrigins::ALL
  end

  test "data_origins priority ranks custom highest" do
    priority = ReferrerSources::DataOrigins::PRIORITY
    assert priority[ReferrerSources::DataOrigins::CUSTOM] > priority[ReferrerSources::DataOrigins::MATOMO_SEARCH]
    assert priority[ReferrerSources::DataOrigins::MATOMO_SEARCH] > priority[ReferrerSources::DataOrigins::SNOWPLOW]
  end

  # ==========================================
  # Scope tests
  # ==========================================

  test "search scope returns only search medium" do
    create_sources_for_scope_tests
    results = ReferrerSource.search

    assert results.all? { |r| r.medium == ReferrerSources::Mediums::SEARCH }
  end

  test "social scope returns only social medium" do
    create_sources_for_scope_tests
    results = ReferrerSource.social

    assert results.all? { |r| r.medium == ReferrerSources::Mediums::SOCIAL }
  end

  test "spam scope returns only spam records" do
    create_sources_for_scope_tests
    results = ReferrerSource.spam

    assert results.all?(&:is_spam)
  end

  test "not_spam scope excludes spam records" do
    create_sources_for_scope_tests
    results = ReferrerSource.not_spam

    assert results.none?(&:is_spam)
  end

  test "by_domain finds exact domain match" do
    referrer_source.save!
    result = ReferrerSource.by_domain("google.com")

    assert_equal referrer_source, result
  end

  test "by_domain returns nil for no match" do
    result = ReferrerSource.by_domain("nonexistent.com")

    assert_nil result
  end

  private

  def referrer_source
    @referrer_source ||= ReferrerSource.new(
      domain: "google.com",
      source_name: "Google",
      medium: ReferrerSources::Mediums::SEARCH,
      keyword_param: "q",
      is_spam: false,
      data_origin: ReferrerSources::DataOrigins::MATOMO_SEARCH
    )
  end

  def create_sources_for_scope_tests
    ReferrerSource.create!(
      domain: "google.com",
      source_name: "Google",
      medium: ReferrerSources::Mediums::SEARCH,
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
      source_name: "Spam Site",
      medium: ReferrerSources::Mediums::SOCIAL,
      is_spam: true,
      data_origin: ReferrerSources::DataOrigins::MATOMO_SPAM
    )
  end
end
