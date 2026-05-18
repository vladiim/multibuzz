# frozen_string_literal: true

require "test_helper"

module Identities
  class FbcCookieTest < ActiveSupport::TestCase
    test "renders fb.1.{ms}.{fbclid} from fbclid + capture time" do
      captured_at = Time.utc(2026, 5, 10, 14, 0, 0)
      cookie = FbcCookie.new(fbclid: "AbC123", captured_at: captured_at)

      assert_equal "fb.1.1778421600000.AbC123", cookie.to_s
    end

    test "returns nil when fbclid is blank" do
      assert_nil FbcCookie.new(fbclid: nil, captured_at: Time.current).to_s
      assert_nil FbcCookie.new(fbclid: "", captured_at: Time.current).to_s
    end

    test "preserves sub-second precision in the millisecond field" do
      captured_at = Time.at(1_700_000_000.123)
      cookie = FbcCookie.new(fbclid: "X", captured_at: captured_at)

      assert_equal "fb.1.1700000000123.X", cookie.to_s
    end
  end
end
