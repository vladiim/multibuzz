# frozen_string_literal: true

require "test_helper"

module AdDestinations
  module Meta
    class PayloadBuilderTest < ActiveSupport::TestCase
      # ── Top-level event fields ──

      test "event_name comes from destination event_type_mapping" do
        destination = build_destination(event_type_mapping: { "Lead" => { "meta_event" => "Lead" } })
        conversion = build_conversion(conversion_type: "Lead")

        assert_equal "Lead", build(conversion: conversion, destination: destination).dig(:data, 0, :event_name)
      end

      test "event_name falls back to conversion_type when mapping is absent" do
        conversion = build_conversion(conversion_type: "Tour Booked")

        assert_equal "Tour Booked", build(conversion: conversion).dig(:data, 0, :event_name)
      end

      test "event_time is converted_at as unix seconds" do
        ts = Time.utc(2026, 5, 10, 14, 0, 0)
        conversion = build_conversion(converted_at: ts)

        assert_equal ts.to_i, build(conversion: conversion).dig(:data, 0, :event_time)
      end

      test "event_id is the conversion's idempotency_key" do
        conversion = build_conversion(idempotency_key: "conv_abc123")

        assert_equal "conv_abc123", build(conversion: conversion).dig(:data, 0, :event_id)
      end

      test "action_source is always website for v1" do
        assert_equal "website", build.dig(:data, 0, :action_source)
      end

      # ── user_data hashing semantics ──

      test "external_id em ph fn ln are passed through as already-hashed values in arrays" do
        match_keys = build_match_keys(
          external_id: "ext_hash_64x",
          em: "em_hash_64x", ph: "ph_hash_64x",
          fn: "fn_hash_64x", ln: "ln_hash_64x"
        )
        user_data = build(match_keys: match_keys).dig(:data, 0, :user_data)

        expected = {
          external_id: [ "ext_hash_64x" ],
          em: [ "em_hash_64x" ],
          ph: [ "ph_hash_64x" ],
          fn: [ "fn_hash_64x" ],
          ln: [ "ln_hash_64x" ]
        }

        assert_equal expected, user_data.slice(:external_id, :em, :ph, :fn, :ln)
      end

      test "country is hashed at payload time (Meta requires hashed)" do
        match_keys = build_match_keys(country: "au")
        user_data = build(match_keys: match_keys).dig(:data, 0, :user_data)

        assert_equal [ Identities::Normaliser.sha256("au") ], user_data[:country]
      end

      test "zp is hashed at payload time" do
        match_keys = build_match_keys(zp: "2000")
        user_data = build(match_keys: match_keys).dig(:data, 0, :user_data)

        assert_equal [ Identities::Normaliser.sha256("2000") ], user_data[:zp]
      end

      test "fbp passes through as a raw string (never hashed)" do
        match_keys = build_match_keys(fbp: "fb.1.1700000000000.1234567890")
        user_data = build(match_keys: match_keys).dig(:data, 0, :user_data)

        assert_equal "fb.1.1700000000000.1234567890", user_data[:fbp]
      end

      test "fbc passes through as a raw string (never hashed)" do
        match_keys = build_match_keys(fbc: "fb.1.1700000000001.AbC")
        user_data = build(match_keys: match_keys).dig(:data, 0, :user_data)

        assert_equal "fb.1.1700000000001.AbC", user_data[:fbc]
      end

      test "user_data omits keys with nil values" do
        match_keys = build_match_keys # all nils
        user_data = build(match_keys: match_keys).dig(:data, 0, :user_data)

        assert_empty user_data
      end

      # ── Privacy posture ──

      test "user_data never contains client_ip_address" do
        match_keys = build_match_keys(em: "em_hash_64x")
        user_data = build(match_keys: match_keys).dig(:data, 0, :user_data)

        refute user_data.key?(:client_ip_address)
        refute user_data.key?(:ip_address)
      end

      test "user_data never contains client_user_agent" do
        match_keys = build_match_keys(em: "em_hash_64x")
        user_data = build(match_keys: match_keys).dig(:data, 0, :user_data)

        refute user_data.key?(:client_user_agent)
        refute user_data.key?(:user_agent)
      end

      # ── custom_data ──

      test "custom_data carries value + currency when revenue is present" do
        conversion = build_conversion(revenue: BigDecimal("99.99"), currency: "AUD")

        assert_equal({ value: 99.99, currency: "AUD" }, build(conversion: conversion).dig(:data, 0, :custom_data))
      end

      test "custom_data is omitted when revenue is nil" do
        conversion = build_conversion(revenue: nil)

        assert_nil build(conversion: conversion).dig(:data, 0, :custom_data)
      end

      private

      def build(conversion: nil, destination: nil, match_keys: nil)
        PayloadBuilder.new(
          conversion: conversion || build_conversion,
          destination: destination || build_destination,
          match_keys: match_keys || build_match_keys
        ).call
      end

      def build_conversion(**overrides)
        defaults = {
          conversion_type: "Lead",
          converted_at: Time.current,
          idempotency_key: "evt_test_#{SecureRandom.hex(4)}",
          revenue: nil,
          currency: nil
        }
        OpenStruct.new(defaults.merge(overrides))
      end

      def build_destination(**overrides)
        defaults = { event_type_mapping: {} }
        OpenStruct.new(defaults.merge(overrides))
      end

      def build_match_keys(**overrides)
        Conversions::MatchKeys.new(
          external_id: nil, em: nil, ph: nil, fn: nil, ln: nil,
          country: nil, zp: nil, fbp: nil, fbc: nil,
          gclid: nil, gbraid: nil, wbraid: nil
        ).then { |defaults| defaults.with(**overrides) }
      end
    end
  end
end
