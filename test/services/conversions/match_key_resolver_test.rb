# frozen_string_literal: true

require "test_helper"

module Conversions
  class MatchKeyResolverTest < ActiveSupport::TestCase
    # ── Identity-sourced fields ──

    test "external_id is SHA-256 of identity.external_id" do
      identity = create_identity(external_id: "user_42", traits: {})
      conversion = create_conversion(identity: identity)

      assert_equal Identities::Normaliser.sha256("user_42"), resolve(conversion).external_id
    end

    test "external_id is nil when conversion has no identity" do
      conversion = create_conversion(identity: nil)

      assert_nil resolve(conversion).external_id
    end

    test "em / ph / fn / ln pass through identity hashed columns" do
      identity = create_identity(
        external_id: "user_pii",
        traits: { email: "user@example.com", phone: "+14155551234", first_name: "Jane", last_name: "Doe" }
      )
      keys = resolve(create_conversion(identity: identity)).to_h.slice(:em, :ph, :fn, :ln)

      expected = {
        em: Identities::Normaliser.hash_email("user@example.com"),
        ph: Identities::Normaliser.hash_phone("+14155551234"),
        fn: Identities::Normaliser.hash_name("jane"),
        ln: Identities::Normaliser.hash_name("doe")
      }

      assert_equal expected, keys
    end

    test "identity-sourced fields are nil when conversion has no identity" do
      keys = resolve(create_conversion(identity: nil)).to_h.slice(:em, :ph, :fn, :ln)

      assert_equal({ em: nil, ph: nil, fn: nil, ln: nil }, keys)
    end

    # ── Session-sourced fields ──

    test "country / zp / fbp / fbc pass through session columns" do
      session = create_session_with_match_keys(
        country: "au", postal_code: "2000",
        fbp: "fb.1.1700000000000.1234567890",
        fbc: "fb.1.1700000000001.AbC"
      )
      keys = resolve(create_conversion(session: session)).to_h.slice(:country, :zp, :fbp, :fbc)

      expected = {
        country: "au",
        zp: "2000",
        fbp: "fb.1.1700000000000.1234567890",
        fbc: "fb.1.1700000000001.AbC"
      }

      assert_equal expected, keys
    end

    test "session-sourced fields are nil when conversion has no session" do
      keys = resolve(create_conversion(session: nil)).to_h.slice(:country, :zp, :fbp, :fbc)

      assert_equal({ country: nil, zp: nil, fbp: nil, fbc: nil }, keys)
    end

    # ── Click-ID fields ──

    test "gclid prefers top-level column over click_ids JSONB" do
      session = create_session_with_match_keys(gclid: "TopLevelGclid", click_ids: { gclid: "JsonbGclid" })
      conversion = create_conversion(session: session)

      assert_equal "TopLevelGclid", resolve(conversion).gclid
    end

    test "gclid falls back to click_ids JSONB when top-level column is nil" do
      session = create_session_with_match_keys(gclid: nil, click_ids: { gclid: "OnlyJsonb" })
      conversion = create_conversion(session: session)

      assert_equal "OnlyJsonb", resolve(conversion).gclid
    end

    test "gbraid and wbraid come from click_ids JSONB" do
      session = create_session_with_match_keys(click_ids: { gbraid: "GbraidVal", wbraid: "WbraidVal" })
      conversion = create_conversion(session: session)
      keys = resolve(conversion)

      assert_equal "GbraidVal", keys.gbraid
      assert_equal "WbraidVal", keys.wbraid
    end

    # ── Sufficiency predicates ──

    test "meta_sufficient? returns true when external_id is present" do
      identity = create_identity(external_id: "u_1", traits: {})

      assert_predicate resolve(create_conversion(identity: identity)), :meta_sufficient?
    end

    test "meta_sufficient? returns true when fbc alone is present" do
      session = create_session_with_match_keys(fbc: "fb.1.1700000000000.X")

      assert_predicate resolve(create_conversion(identity: nil, session: session)), :meta_sufficient?
    end

    test "meta_sufficient? returns false when no usable identifiers" do
      refute_predicate resolve(create_conversion(identity: nil)), :meta_sufficient?
    end

    test "google_sufficient? returns true when gclid alone is present" do
      session = create_session_with_match_keys(gclid: "Cj0KEXAMPLE")

      assert_predicate resolve(create_conversion(identity: nil, session: session)), :google_sufficient?
    end

    test "google_sufficient? returns true when hashed email is present" do
      identity = create_identity(external_id: "u_em", traits: { email: "user@example.com" })

      assert_predicate resolve(create_conversion(identity: identity)), :google_sufficient?
    end

    test "google_sufficient? returns false when only external_id is present" do
      identity = create_identity(external_id: "u_only_xid", traits: {})

      refute_predicate resolve(create_conversion(identity: identity)), :google_sufficient?
    end

    # ── No IP / UA, ever ──

    test "MatchKeys does not expose client_ip_address" do
      refute_respond_to resolve(create_conversion(identity: nil)), :client_ip_address
      refute_respond_to resolve(create_conversion(identity: nil)), :ip_address
    end

    test "MatchKeys does not expose client_user_agent" do
      refute_respond_to resolve(create_conversion(identity: nil)), :client_user_agent
      refute_respond_to resolve(create_conversion(identity: nil)), :user_agent
    end

    private

    def resolve(conversion) = MatchKeyResolver.new(conversion).call

    def account = @account ||= accounts(:one)
    def visitor = @visitor ||= visitors(:one)

    def create_identity(external_id:, traits:)
      Identities::IdentificationService.new(account, { user_id: external_id, traits: traits }, is_test: false).call
      account.identities.find_by!(external_id: external_id)
    end

    def create_session_with_match_keys(**attributes)
      defaults = { session_id: "sess_#{SecureRandom.hex(8)}", visitor: visitor, started_at: 1.minute.ago, last_activity_at: 1.minute.ago }
      account.sessions.create!(defaults.merge(attributes))
    end

    def create_conversion(identity: nil, session: nil)
      account.conversions.create!(
        visitor: visitor,
        session_id: session&.id,
        identity: identity,
        conversion_type: "signup",
        converted_at: Time.current
      )
    end
  end
end
