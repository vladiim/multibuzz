# frozen_string_literal: true

# Scrubs Meta-API secrets and customer identifiers out of strings before they
# get serialized into a VCR cassette.
#
# Used by VCR's `before_record` hook. Exposed as a module so the regex list is
# unit-testable.
module VcrFilters
  SUBSTITUTIONS = [
    [ /access_token=[^&"\s]+/,                  "access_token=<META_ACCESS_TOKEN>" ],
    [ /appsecret_proof=[^&"\s]+/,               "appsecret_proof=<APPSECRET_PROOF>" ],
    [ /fb_exchange_token=[^&"\s]+/,             "fb_exchange_token=<FB_EXCHANGE_TOKEN>" ],
    [ /client_secret=[^&"\s]+/,                 "client_secret=<META_APP_SECRET>" ],
    [ /(\?|&)code=[^&"\s]+/,                    '\1code=<OAUTH_CODE>' ],
    [ /"access_token"\s*:\s*"[^"]+"/,           '"access_token":"<META_ACCESS_TOKEN>"' ],
    [ /"app_secret"\s*:\s*"[^"]+"/,             '"app_secret":"<META_APP_SECRET>"' ],
    [ /act_\d{6,}/,                             "act_TEST_REDACTED" ]
  ].freeze

  def self.scrub(value)
    return value if value.nil? || value.to_s.empty?

    SUBSTITUTIONS.reduce(value.to_s) { |acc, (pattern, replacement)| acc.gsub(pattern, replacement) }
  end
end
