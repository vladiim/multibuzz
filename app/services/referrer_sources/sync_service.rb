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
      log_info("Starting referrer source sync")

      fetch_and_parse_sources
      return all_failed_result if all_sources_failed?

      log_info("Parsed #{parsed_records.count} records, #{deduplicated_records.count} unique domains")

      upsert_records
      invalidate_cache

      log_info("Sync complete: #{stats[:created]} created, #{stats[:updated]} updated, #{stats[:skipped]} skipped")

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

    HTTP_TIMEOUT = 30
    MAX_RETRIES = 3
    RETRYABLE_ERRORS = [Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED].freeze

    def fetch_source(url, source_key)
      log_info("Fetching #{source_key} from #{url}")
      fetch_with_retry(url, source_key)
    end

    def fetch_with_retry(url, source_key, attempt: 1)
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      uri = URI.parse(url)
      response = http_get(uri)
      elapsed = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time).round(2)

      if response.is_a?(Net::HTTPSuccess)
        log_info("Fetched #{source_key} in #{elapsed}s (#{response.body.bytesize} bytes)")
        return response.body
      end

      handle_http_error(source_key, response.code)
    rescue *RETRYABLE_ERRORS => e
      retry_or_fail(url, source_key, attempt, e)
    rescue StandardError => e
      log_error("Failed to fetch #{source_key}: #{e.message}")
      errors << "Failed to fetch #{source_key}: #{e.message}"
      nil
    end

    def retry_or_fail(url, source_key, attempt, error)
      if attempt < MAX_RETRIES
        delay = backoff_delay(attempt)
        log_info("Retry #{attempt}/#{MAX_RETRIES} for #{source_key} after #{delay}s (#{error.class})")
        sleep(delay)
        fetch_with_retry(url, source_key, attempt: attempt + 1)
      else
        log_error("Failed to fetch #{source_key} after #{MAX_RETRIES} attempts: #{error.message}")
        errors << "Failed to fetch #{source_key} after #{MAX_RETRIES} attempts: #{error.message}"
        nil
      end
    end

    def backoff_delay(attempt)
      2**(attempt - 1) # 1s, 2s, 4s
    end

    def handle_http_error(source_key, code)
      log_error("Failed to fetch #{source_key}: HTTP #{code}")
      errors << "Failed to fetch #{source_key}: HTTP #{code}"
      nil
    end

    def http_get(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
    end

    def all_sources_failed?
      parsed_records.empty? && errors.present?
    end

    def all_failed_result
      error_result(errors)
    end

    def upsert_records
      ActiveRecord::Base.transaction do
        ReferrerSource.upsert_all(
          timestamped_records,
          unique_by: :domain,
          update_only: [:source_name, :medium, :keyword_param, :is_spam, :data_origin]
        ) if records_to_upsert.any?
      end
    end

    def timestamped_records
      @timestamped_records ||= records_to_upsert.map { |r| r.merge(created_at: now, updated_at: now) }
    end

    def records_to_upsert
      @records_to_upsert ||= deduplicated_records.select { |r| should_upsert?(r) }
    end

    def deduplicated_records
      @deduplicated_records ||= parsed_records
        .group_by { |r| r[:domain] }
        .transform_values { |records| highest_priority_record(records) }
        .values
    end

    def highest_priority_record(records)
      records.max_by { |r| priority_for(r[:data_origin]) }
    end

    def should_upsert?(record)
      existing_origin = existing_origins[record[:domain]]
      return true unless existing_origin

      priority_for(record[:data_origin]) >= priority_for(existing_origin)
    end

    def existing_origins
      @existing_origins ||= ReferrerSource
        .where(domain: deduplicated_domains)
        .pluck(:domain, :data_origin)
        .to_h
    end

    def deduplicated_domains
      @deduplicated_domains ||= deduplicated_records.map { |r| r[:domain] }
    end

    def priority_for(origin)
      DataOrigins::PRIORITY[origin] || 0
    end

    def now
      @now ||= Time.current
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
      @stats ||= {
        created: new_domains.count,
        updated: updated_domains.count,
        skipped: skipped_count
      }
    end

    def new_domains
      @new_domains ||= records_to_upsert.reject { |r| existing_origins.key?(r[:domain]) }
    end

    def updated_domains
      @updated_domains ||= records_to_upsert.select { |r| existing_origins.key?(r[:domain]) }
    end

    def skipped_count
      parsed_records.count - records_to_upsert.count
    end

    def log_info(message)
      Rails.logger.info("[ReferrerSources::SyncService] #{message}")
    end

    def log_error(message)
      Rails.logger.error("[ReferrerSources::SyncService] #{message}")
    end
  end
end
