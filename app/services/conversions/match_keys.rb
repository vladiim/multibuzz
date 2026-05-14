# frozen_string_literal: true

# Value object holding the identity match keys mbuzz sends to ad
# platforms during conversion feedback. Field names follow mbuzz's
# internal conventions; platform PayloadBuilder classes map them to
# Meta CAPI keys (`em`, `ph`, `fbc`, etc.) and Google EC for Leads keys
# (`hashed_email`, `hashed_phone_number`, `gclid`, etc.).
#
# **No `client_ip_address`, no `client_user_agent`, ever.** mbuzz
# declines to send raw IP / UA to either platform. See
# `lib/specs/conversion_feedback_spec.md` "No IP, no UA, ever".
module Conversions
  MatchKeys = Data.define(
    :external_id, # SHA-256 of identity.external_id (customer's CRM user ID)
    :em,          # SHA-256 lowercased email
    :ph,          # SHA-256 E.164 phone
    :fn,          # SHA-256 lowercased first name
    :ln,          # SHA-256 lowercased last name
    :country,     # ISO-2 lowercase. Hashed by Meta dispatcher; raw for Google.
    :zp,          # postal code. Hashed by Meta dispatcher; raw for Google.
    :fbp,         # _fbp browser cookie (Meta only). Never hashed.
    :fbc,         # _fbc click cookie (Meta only). Never hashed.
    :gclid,
    :gbraid,
    :wbraid
  ) do
    META_SUFFICIENT_FIELDS   = %i[external_id em ph fbc fbp].freeze
    GOOGLE_SUFFICIENT_FIELDS = %i[em ph gclid gbraid wbraid].freeze

    def meta_sufficient?
      META_SUFFICIENT_FIELDS.any? { |field| public_send(field).present? }
    end

    def google_sufficient?
      GOOGLE_SUFFICIENT_FIELDS.any? { |field| public_send(field).present? }
    end
  end
end
