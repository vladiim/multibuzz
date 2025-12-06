require "test_helper"

class ReferrerSources::SyncServiceTest < ActiveSupport::TestCase
  test "creates new referrer sources" do
    assert_difference "ReferrerSource.count", 3 do
      result = service.call

      assert result[:success]
      assert_equal 3, result[:stats][:created]
    end
  end

  test "updates existing referrer sources" do
    ReferrerSource.create!(
      domain: "google.com",
      source_name: "Old Name",
      medium: ReferrerSources::Mediums::SEARCH,
      data_origin: ReferrerSources::DataOrigins::MATOMO_SEARCH
    )

    result = service.call

    assert result[:success]
    assert_equal 1, result[:stats][:updated]
    assert_equal "Google", ReferrerSource.find_by(domain: "google.com").source_name
  end

  test "respects data origin priority - custom not overwritten" do
    ReferrerSource.create!(
      domain: "google.com",
      source_name: "Custom Google",
      medium: ReferrerSources::Mediums::SEARCH,
      data_origin: ReferrerSources::DataOrigins::CUSTOM
    )

    service.call

    assert_equal "Custom Google", ReferrerSource.find_by(domain: "google.com").source_name
  end

  test "respects data origin priority - matomo overwrites snowplow" do
    ReferrerSource.create!(
      domain: "google.com",
      source_name: "Snowplow Google",
      medium: ReferrerSources::Mediums::SEARCH,
      data_origin: ReferrerSources::DataOrigins::SNOWPLOW
    )

    service.call

    # Matomo has higher priority, should overwrite
    assert_equal "Google", ReferrerSource.find_by(domain: "google.com").source_name
    assert_equal ReferrerSources::DataOrigins::MATOMO_SEARCH,
      ReferrerSource.find_by(domain: "google.com").data_origin
  end

  test "returns stats for created updated and skipped" do
    ReferrerSource.create!(
      domain: "google.com",
      source_name: "Custom Google",
      medium: ReferrerSources::Mediums::SEARCH,
      data_origin: ReferrerSources::DataOrigins::CUSTOM
    )

    result = service.call

    assert result[:success]
    assert_equal 2, result[:stats][:created]  # facebook + spam
    assert_equal 0, result[:stats][:updated]  # google skipped due to priority
    assert_equal 2, result[:stats][:skipped]  # google from matomo + google from snowplow
  end

  test "marks spam records correctly" do
    service.call

    spam_record = ReferrerSource.find_by(domain: "spam-site.com")
    assert spam_record.is_spam
  end

  test "sets correct medium for each source type" do
    service.call

    assert_equal ReferrerSources::Mediums::SEARCH,
      ReferrerSource.find_by(domain: "google.com").medium
    assert_equal ReferrerSources::Mediums::SOCIAL,
      ReferrerSource.find_by(domain: "facebook.com").medium
  end

  test "invalidates cache after sync" do
    Rails.cache.write("referrer_sources/domain/google.com", { source_name: "Cached" })

    service.call

    assert_nil Rails.cache.read("referrer_sources/domain/google.com")
  end

  test "returns error when all sources empty" do
    empty_service = ReferrerSources::SyncService.new(
      fetched_content: {
        matomo_search: "",
        matomo_social: "",
        matomo_spam: "",
        snowplow: ""
      }
    )

    result = empty_service.call

    # Empty content is not an error, just no records
    assert result[:success]
    assert_equal 0, result[:stats][:created]
  end

  private

  def service
    @service ||= ReferrerSources::SyncService.new(fetched_content: test_content)
  end

  def test_content
    {
      matomo_search: matomo_search_yaml,
      matomo_social: matomo_social_yaml,
      matomo_spam: matomo_spam_txt,
      snowplow: snowplow_json
    }
  end

  def matomo_search_yaml
    <<~YAML
      Google:
        urls:
          - google.com
        params:
          - q
    YAML
  end

  def matomo_social_yaml
    <<~YAML
      Facebook:
        - facebook.com
    YAML
  end

  def matomo_spam_txt
    "spam-site.com"
  end

  def snowplow_json
    # Snowplow has google.com too, but lower priority than matomo
    {
      "search" => {
        "Google" => { "domains" => ["google.com"], "parameters" => ["q"] }
      }
    }.to_json
  end
end
