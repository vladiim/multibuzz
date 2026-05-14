# frozen_string_literal: true

require "test_helper"

module Identities
  class PhoneNormaliserTest < ActiveSupport::TestCase
    test "preserves explicit + prefix" do
      assert_equal "+61412345678", PhoneNormaliser.new("+61 412 345 678").call
    end

    test "strips formatting characters" do
      assert_equal "+14155551234", PhoneNormaliser.new("+1 (415) 555-1234").call
      assert_equal "+14155551234", PhoneNormaliser.new("+1.415.555.1234").call
    end

    test "uses default_country_code when input has no plus prefix" do
      assert_equal "+14155551234", PhoneNormaliser.new("(415) 555-1234", default_country_code: "1").call
      assert_equal "+14155551234", PhoneNormaliser.new("415-555-1234", default_country_code: "1").call
    end

    test "does not double-prepend default_country_code when already present in digits" do
      assert_equal "+14155551234", PhoneNormaliser.new("1 415 555 1234", default_country_code: "1").call
    end

    test "returns nil when input has no digits" do
      assert_nil PhoneNormaliser.new("not a phone").call
      assert_nil PhoneNormaliser.new("").call
      assert_nil PhoneNormaliser.new(nil).call
    end

    test "returns nil when no plus prefix and no default_country_code" do
      assert_nil PhoneNormaliser.new("4155551234").call
    end
  end
end
