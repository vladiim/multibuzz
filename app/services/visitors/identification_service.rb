module Visitors
  class IdentificationService
    COOKIE_NAME = "_multibuzz_vid"
    COOKIE_EXPIRY = 1.year

    def initialize(request, account)
      @request = request
      @account = account
    end

    def call
      { visitor_id: visitor_id, set_cookie: set_cookie_header }
    end

    private

    attr_reader :request, :account

    def visitor_id
      @visitor_id ||= extract_visitor_id || generate_visitor_id
    end

    def extract_visitor_id
      request.cookies[COOKIE_NAME]
    end

    def generate_visitor_id
      SecureRandom.hex(32)
    end

    def set_cookie_header
      @set_cookie_header ||= build_set_cookie
    end

    def build_set_cookie
      "#{COOKIE_NAME}=#{visitor_id}; " \
      "Expires=#{cookie_expiry.httpdate}; " \
      "Path=/; " \
      "#{httponly_flag}" \
      "#{secure_flag}" \
      "SameSite=Lax"
    end

    def cookie_expiry
      COOKIE_EXPIRY.from_now
    end

    def httponly_flag
      "HttpOnly; "
    end

    def secure_flag
      Rails.env.production? ? "Secure; " : ""
    end
  end
end
