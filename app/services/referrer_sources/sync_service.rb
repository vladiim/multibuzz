module ReferrerSources
  class SyncService < ApplicationService
    MATOMO_SEARCH_URL = "https://raw.githubusercontent.com/matomo-org/searchengine-and-social-list/master/SearchEngines.yml"
    MATOMO_SOCIAL_URL = "https://raw.githubusercontent.com/matomo-org/searchengine-and-social-list/master/Socials.yml"
    MATOMO_SPAM_URL = "https://raw.githubusercontent.com/matomo-org/referrer-spam-list/master/spammers.txt"
    SNOWPLOW_URL = "https://s3-eu-west-1.amazonaws.com/snowplow-hosted-assets/third-party/referer-parser/referers-latest.json"

    SOURCES = {
      matomo_search: { url: MATOMO_SEARCH_URL, parser: Parsers::MatomoSearchParser },
      matomo_social: { url: MATOMO_SOCIAL_URL, parser: Parsers::MatomoSocialParser },
      matomo_spam: { url: MATOMO_SPAM_URL, parser: Parsers::MatomoSpamParser },
      snowplow: { url: SNOWPLOW_URL, parser: Parsers::SnowplowParser }
    }.freeze

    # Allow injecting fetched content for testing
    def initialize(fetched_content: nil)
      @fetched_content = fetched_content
    end

    private

    attr_reader :fetched_content

    def run
      fetch_and_parse_sources
      return all_failed_result if all_sources_failed?

      upsert_records
      invalidate_cache

      success_result(stats: stats, errors: errors)
    end

    def fetch_and_parse_sources
      SOURCES.each do |source_key, config|
        content = fetched_content&.dig(source_key) || fetch_source(config[:url], source_key)
        next unless content

        records = config[:parser].new(content).call
        @parsed_records ||= []
        @parsed_records.concat(records)
      end
    end

    def fetch_source(url, source_key)
      uri = URI.parse(url)
      response = Net::HTTP.get_response(uri)

      return response.body if response.is_a?(Net::HTTPSuccess)

      errors << "Failed to fetch #{source_key}: HTTP #{response.code}"
      nil
    rescue StandardError => e
      errors << "Failed to fetch #{source_key}: #{e.message}"
      nil
    end

    def all_sources_failed?
      parsed_records.empty? && errors.present?
    end

    def all_failed_result
      error_result(errors)
    end

    def upsert_records
      parsed_records.each do |record|
        upsert_record(record)
      end
    end

    def upsert_record(record)
      existing = ReferrerSource.find_by(domain: record[:domain])

      if existing.nil?
        ReferrerSource.create!(record)
        stats[:created] += 1
      elsif should_update?(existing, record)
        existing.update!(record.except(:domain))
        stats[:updated] += 1
      else
        stats[:skipped] += 1
      end
    end

    def should_update?(existing, new_record)
      existing_priority = DataOrigins::PRIORITY[existing.data_origin] || 0
      new_priority = DataOrigins::PRIORITY[new_record[:data_origin]] || 0

      new_priority >= existing_priority
    end

    def invalidate_cache
      Rails.cache.delete_matched("referrer_sources/*")
    end

    def parsed_records
      @parsed_records ||= []
    end

    def errors
      @errors ||= []
    end

    def stats
      @stats ||= { created: 0, updated: 0, skipped: 0 }
    end
  end
end
