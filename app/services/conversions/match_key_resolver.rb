# frozen_string_literal: true

# Assembles a `Conversions::MatchKeys` value object for a given
# `Conversion` by pulling identity-sourced fields from `Identity`'s
# typed hashed columns and session-sourced fields from `Session`'s
# match-key columns + `click_ids` JSONB. Returns nil values for any
# field whose source data is absent — the dispatcher decides whether
# the resulting match-key set is sufficient via
# `MatchKeys#meta_sufficient?` / `#google_sufficient?`.
#
# `external_id` is hashed here (SHA-256 of `Identity#external_id`,
# the customer's CRM user ID) because mbuzz stores `external_id` raw
# for cross-system lookup, and Meta requires it hashed.
module Conversions
  class MatchKeyResolver
    def initialize(conversion)
      @conversion = conversion
    end

    def call
      MatchKeys.new(**identity_fields, **session_fields, **click_id_fields)
    end

    private

    attr_reader :conversion

    def identity_fields
      {
        external_id: hashed_external_id,
        em: identity&.email_sha256,
        ph: identity&.phone_e164_sha256,
        fn: identity&.first_name_sha256,
        ln: identity&.last_name_sha256
      }
    end

    def session_fields
      {
        country: session&.country,
        zp: session&.postal_code,
        fbp: session&.fbp,
        fbc: session&.fbc
      }
    end

    def click_id_fields
      {
        gclid: gclid,
        gbraid: click_id_value(ClickIdentifiers::GBRAID),
        wbraid: click_id_value(ClickIdentifiers::WBRAID)
      }
    end

    def identity
      @identity ||= conversion.identity
    end

    def session
      return @session if defined?(@session)

      @session = conversion.session_id ? conversion.account.sessions.find_by(id: conversion.session_id) : nil
    end

    def hashed_external_id
      return nil if identity&.external_id.blank?

      Identities::Normaliser.sha256(identity.external_id)
    end

    def gclid
      session&.gclid.presence || click_id_value(ClickIdentifiers::GCLID)
    end

    def click_id_value(key)
      click_ids[key.to_sym] || click_ids[key]
    end

    def click_ids
      @click_ids ||= session&.click_ids || {}
    end
  end
end
