# frozen_string_literal: true

# Normalises a free-form phone string into E.164 format (`+CCNNNNNN`)
# suitable for SHA-256 hashing as a Meta `ph` or Google
# `hashed_phone_number` match key. Returns nil when the input has no
# digits, or has digits but no country-code source (no `+` prefix and no
# `default_country_code:` argument).
#
# Examples:
#   PhoneNormaliser.new("+1 (415) 555-1234").call               # => "+14155551234"
#   PhoneNormaliser.new("+61 412 345 678").call                 # => "+61412345678"
#   PhoneNormaliser.new("(415) 555-1234", default_country_code: "1").call # => "+14155551234"
#   PhoneNormaliser.new("4155551234").call                      # => nil (no country code source)
#   PhoneNormaliser.new("not a phone").call                     # => nil
module Identities
  class PhoneNormaliser
    PLUS_PREFIX = "+"

    def initialize(input, default_country_code: nil)
      @input = input.to_s
      @default_country_code = default_country_code&.to_s
    end

    def call
      return nil unless digits.present?
      return "#{PLUS_PREFIX}#{digits}" if explicitly_prefixed?
      return "#{PLUS_PREFIX}#{default_country_code}#{digits_without_default_cc}" if default_country_code

      nil
    end

    private

    attr_reader :input, :default_country_code

    def digits
      @digits ||= input.tr_s("^0-9", "")
    end

    def explicitly_prefixed?
      input.lstrip.start_with?(PLUS_PREFIX)
    end

    def digits_without_default_cc
      digits.delete_prefix(default_country_code)
    end
  end
end
