# frozen_string_literal: true

# Pure normalisation + hashing helpers for identity match keys sent to ad
# platforms (Meta CAPI, Google EC for Leads). Every input is trimmed,
# lowercased, and (where applicable) stripped of formatting characters
# before SHA-256 hashing.
#
# Phone normalisation lives in `Identities::PhoneNormaliser` because
# country-code resolution branches non-trivially. Email and name are
# simple enough to stay inline as functional chains.
#
# fbp / fbc / country / postal_code are NOT handled here because they
# are not symmetrically hashed across platforms (Meta hashes country +
# postcode; Google does not). The dispatcher applies platform-specific
# rules.
#
# References:
# - Meta: https://developers.facebook.com/docs/marketing-api/conversions-api/parameters/customer-information-parameters
# - Google: https://developers.google.com/google-ads/api/docs/conversions/enhanced-conversions/leads
module Identities
  module Normaliser
    SHA256_HEX_PATTERN = /\A[a-f0-9]{64}\z/

    module_function

    # ── normalisers ──

    def normalise_email(input)
      input.to_s.strip.downcase.presence
    end

    def normalise_phone_e164(input, default_country_code: nil)
      PhoneNormaliser.new(input, default_country_code: default_country_code).call
    end

    def normalise_name(input)
      ActiveSupport::Inflector.transliterate(input.to_s.strip).downcase.presence
    end

    # ── hashing ──

    def sha256(input)
      return nil if input.blank?

      Digest::SHA256.hexdigest(input.to_s)
    end

    def already_hashed?(input)
      input.is_a?(String) && SHA256_HEX_PATTERN.match?(input)
    end

    # ── composite (normalise + hash) ──

    def hash_email(input)
      already_hashed?(input) ? input : sha256(normalise_email(input))
    end

    def hash_phone(input, default_country_code: nil)
      already_hashed?(input) ? input : sha256(normalise_phone_e164(input, default_country_code: default_country_code))
    end

    def hash_name(input)
      already_hashed?(input) ? input : sha256(normalise_name(input))
    end
  end
end
