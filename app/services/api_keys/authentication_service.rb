module ApiKeys
  class AuthenticationService
    def initialize(authorization_header)
      @authorization_header = authorization_header
    end

    def call
      return missing_header_error if header_missing?
      return malformed_header_error unless header_valid?
      return invalid_key_error unless api_key_record
      return revoked_key_error if api_key_record.revoked?

      api_key_record.record_usage!
      success_result
    end

    private

    attr_reader :authorization_header

    def header_missing?
      authorization_header.nil? || authorization_header.strip.empty?
    end

    def header_valid?
      normalized_header.match?(/\Abearer\s+sk_(test|live)_\w+\z/i)
    end

    def normalized_header
      @normalized_header ||= authorization_header.to_s.strip
    end

    def extracted_key
      @extracted_key ||= normalized_header.split(/\s+/, 2).last
    end

    def key_digest
      @key_digest ||= Digest::SHA256.hexdigest(extracted_key)
    end

    def api_key_record
      @api_key_record ||= ApiKey.find_by(key_digest: key_digest)
    end

    def success_result
      {
        success: true,
        account: api_key_record.account,
        api_key: api_key_record
      }
    end

    def missing_header_error
      {
        success: false,
        error: "Missing Authorization header",
        error_code: :missing_header
      }
    end

    def malformed_header_error
      {
        success: false,
        error: "Authorization header must be in format: Bearer sk_{env}_{key}",
        error_code: :malformed_header
      }
    end

    def invalid_key_error
      {
        success: false,
        error: "Invalid or expired API key",
        error_code: :invalid_key
      }
    end

    def revoked_key_error
      {
        success: false,
        error: "API key has been revoked",
        error_code: :revoked_key
      }
    end
  end
end
