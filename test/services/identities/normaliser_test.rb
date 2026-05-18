# frozen_string_literal: true

require "test_helper"

module Identities
  class NormaliserTest < ActiveSupport::TestCase
    # ── normalise_email ──

    test "normalise_email lowercases and trims" do
      assert_equal "user@example.com", Normaliser.normalise_email("  User@Example.COM  ")
    end

    test "normalise_email returns nil for blank input" do
      assert_nil Normaliser.normalise_email(nil)
      assert_nil Normaliser.normalise_email("")
      assert_nil Normaliser.normalise_email("   ")
    end

    test "normalise_email preserves plus-addressing" do
      assert_equal "user+tag@example.com", Normaliser.normalise_email("  User+Tag@Example.com  ")
    end

    # ── normalise_phone_e164 (delegates to PhoneNormaliser) ──

    test "normalise_phone_e164 delegates to PhoneNormaliser" do
      assert_equal "+14155551234", Normaliser.normalise_phone_e164("+1 (415) 555-1234")
      assert_nil Normaliser.normalise_phone_e164(nil)
    end

    # ── normalise_name ──

    test "normalise_name lowercases trims and strips diacritics" do
      assert_equal "jose", Normaliser.normalise_name("  José  ")
      assert_equal "muller", Normaliser.normalise_name("Müller")
      assert_equal "renee", Normaliser.normalise_name("Renée")
    end

    test "normalise_name returns nil for blank input" do
      assert_nil Normaliser.normalise_name(nil)
      assert_nil Normaliser.normalise_name("")
    end

    # ── sha256 ──

    test "sha256 returns 64-char lowercase hex" do
      digest = Normaliser.sha256("hello")

      assert_equal 64, digest.length
      assert_match(/\A[a-f0-9]{64}\z/, digest)
    end

    test "sha256 matches a known vector" do
      assert_equal "b4c9a289323b21a01c3e940f150eb9b8c542587f1abfd8f0e1cc1ffc5e475514",
        Normaliser.sha256("user@example.com")
    end

    test "sha256 returns nil for blank input" do
      assert_nil Normaliser.sha256(nil)
      assert_nil Normaliser.sha256("")
    end

    # ── composite hashers ──

    test "hash_email normalises then hashes" do
      assert_equal Normaliser.sha256("user@example.com"), Normaliser.hash_email("  User@Example.COM  ")
    end

    test "hash_email passes through input that is already a 64-char hex digest" do
      already_hashed = "a" * 64

      assert_equal already_hashed, Normaliser.hash_email(already_hashed)
    end

    test "hash_phone normalises then hashes" do
      assert_equal Normaliser.sha256("+14155551234"), Normaliser.hash_phone("+1 (415) 555-1234")
    end

    test "hash_name normalises then hashes" do
      assert_equal Normaliser.sha256("jose"), Normaliser.hash_name("  José  ")
    end
  end
end
