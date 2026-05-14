# frozen_string_literal: true

# Canonical trait keys mbuzz recognises in identify-call payloads for
# server-side hashing into match keys (Meta CAPI `em`/`ph`/`fn`/`ln`,
# Google EC for Leads `hashed_email`/`hashed_phone_number`/
# `address_info.hashed_first_name`/`hashed_last_name`).
#
# Customers may include other arbitrary keys in `traits`; only these
# canonical ones are extracted, normalised, and hashed into the typed
# `*_sha256` columns on `identities`. Everything else stays in the
# `traits` JSONB.
module CanonicalIdentityTraits
  EMAIL = "email"
  PHONE = "phone"
  FIRST_NAME = "first_name"
  LAST_NAME = "last_name"

  ALL = [ EMAIL, PHONE, FIRST_NAME, LAST_NAME ].freeze
end
