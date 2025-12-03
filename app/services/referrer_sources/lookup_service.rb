module ReferrerSources
  class LookupService
    CACHE_TTL = 24.hours

    def initialize(referrer)
      @referrer = referrer
    end

    def call
      return nil if referrer.blank?
      return nil unless domain

      cached_lookup || database_lookup
    end

    private

    attr_reader :referrer

    def cached_lookup
      Rails.cache.read(cache_key)
    end

    def database_lookup
      source = find_source
      return nil unless source

      result = build_result(source)
      cache_result(result)
      result
    end

    def find_source
      # Try exact domain first
      ReferrerSource.by_domain(domain) ||
        # Try without subdomain (m.facebook.com -> facebook.com)
        ReferrerSource.by_domain(root_domain)
    end

    def build_result(source)
      {
        source_name: source.source_name,
        medium: source.medium,
        keyword_param: source.keyword_param,
        is_spam: source.is_spam,
        search_term: extract_search_term(source.keyword_param)
      }
    end

    def extract_search_term(param)
      return nil unless param.present?

      uri = URI.parse(referrer)
      params = CGI.parse(uri.query || "")
      value = params[param]&.first
      value&.gsub("+", " ")
    rescue URI::InvalidURIError
      nil
    end

    def cache_result(result)
      Rails.cache.write(cache_key, result, expires_in: CACHE_TTL)
    end

    def cache_key
      "referrer_sources/domain/#{domain}"
    end

    def domain
      @domain ||= extract_domain
    end

    def root_domain
      parts = domain&.split(".")
      return nil unless parts && parts.size >= 2

      parts.last(2).join(".")
    end

    def extract_domain
      uri = URI.parse(referrer)
      host = uri.host&.downcase
      host&.sub(/^www\./, "")
    rescue URI::InvalidURIError
      nil
    end
  end
end
