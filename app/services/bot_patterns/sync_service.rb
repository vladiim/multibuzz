# frozen_string_literal: true

module BotPatterns
  class SyncService < ApplicationService
    UPSTREAM_SOURCES = {
      Sources::CRAWLER_USER_AGENTS => {
        url: Sources::CRAWLER_USER_AGENTS_URL,
        parser: Parsers::CrawlerUserAgentsParser
      },
      Sources::MATOMO_BOTS => {
        url: Sources::MATOMO_BOTS_URL,
        parser: Parsers::MatomoBotsParser
      }
    }.freeze

    HTTP_TIMEOUT = 30
    MAX_RETRIES = 3
    RETRYABLE_ERRORS = [ Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, Errno::ECONNREFUSED ].freeze

    def initialize(fetched_content: nil)
      @fetched_content = fetched_content
    end

    private

    attr_reader :fetched_content

    def run
      fetch_and_parse_sources
      return error_result(errors) if all_sources_failed?

      merge_custom_patterns
      deduplicate!
      load_and_cache!

      log_info("Sync complete: #{patterns.size} patterns loaded")
      success_result(pattern_count: patterns.size)
    end

    def fetch_and_parse_sources
      UPSTREAM_SOURCES.each do |source_key, config|
        content = resolve_content(source_key, config[:url])
        next unless content

        patterns.concat(config[:parser].new(content).call)
      end
    end

    def resolve_content(source_key, url)
      return fetched_content[source_key] if fetched_content&.key?(source_key)

      fetch_source(url, source_key)
    end

    def merge_custom_patterns
      custom_path = Rails.root.join(Sources::CUSTOM_CONFIG_PATH)
      return unless custom_path.exist?

      config = YAML.safe_load_file(custom_path) || {}
      entries = config["patterns"] || []
      entries.each do |entry|
        patterns << { pattern: entry["pattern"], name: entry["name"] || entry["pattern"] }
      end
    rescue Psych::SyntaxError => e
      log_error("Failed to parse custom bot patterns: #{e.message}")
    end

    def deduplicate!
      @patterns = patterns.uniq { |p| p[:pattern] }
    end

    def load_and_cache!
      Rails.cache.write(Sources::CACHE_KEY, patterns)
      Matcher.load!(patterns)
    end

    def all_sources_failed?
      patterns.empty?
    end

    def fetch_source(url, source_key)
      log_info("Fetching #{source_key} from #{url}")
      fetch_with_retry(url, source_key)
    end

    def fetch_with_retry(url, source_key, attempt: 1)
      uri = URI.parse(url)
      response = http_get(uri)

      if response.is_a?(Net::HTTPSuccess)
        log_info("Fetched #{source_key} (#{response.body.bytesize} bytes)")
        return response.body
      end

      log_error("Failed to fetch #{source_key}: HTTP #{response.code}")
      errors << "Failed to fetch #{source_key}: HTTP #{response.code}"
      nil
    rescue *RETRYABLE_ERRORS => e
      retry_or_fail(url, source_key, attempt, e)
    rescue StandardError => e
      log_error("Failed to fetch #{source_key}: #{e.message}")
      errors << "Failed to fetch #{source_key}: #{e.message}"
      nil
    end

    def retry_or_fail(url, source_key, attempt, error)
      if attempt < MAX_RETRIES
        delay = 2**(attempt - 1)
        log_info("Retry #{attempt}/#{MAX_RETRIES} for #{source_key} after #{delay}s")
        sleep(delay)
        fetch_with_retry(url, source_key, attempt: attempt + 1)
      else
        log_error("Failed to fetch #{source_key} after #{MAX_RETRIES} attempts: #{error.message}")
        errors << "Failed to fetch #{source_key} after #{MAX_RETRIES} attempts: #{error.message}"
        nil
      end
    end

    def http_get(uri)
      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
        http.request(Net::HTTP::Get.new(uri))
      end
    end

    def patterns
      @patterns ||= []
    end

    def errors
      @errors ||= []
    end

    def log_info(message)
      Rails.logger.info("[BotPatterns::SyncService] #{message}")
    end

    def log_error(message)
      Rails.logger.error("[BotPatterns::SyncService] #{message}")
    end
  end
end
