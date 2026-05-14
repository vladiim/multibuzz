# frozen_string_literal: true

require "test_helper"

module AdDestinations
  module Meta
    class SourceMatcherTest < ActiveSupport::TestCase
      test "matches a session whose click_ids contain fbclid" do
        session = build_session(click_ids: { "fbclid" => "AbC123" })

        assert SourceMatcher.matches?(session)
      end

      test "matches when fbclid key is a symbol (mixed-typing tolerance)" do
        session = build_session(click_ids: { fbclid: "AbC123" })

        assert SourceMatcher.matches?(session)
      end

      test "does not match a session with only Google click IDs" do
        session = build_session(click_ids: { "gclid" => "Cj0KEXAMPLE" })

        refute SourceMatcher.matches?(session)
      end

      test "does not match a session with no click_ids" do
        session = build_session(click_ids: {})

        refute SourceMatcher.matches?(session)
      end

      test "returns false when session is nil" do
        refute SourceMatcher.matches?(nil)
      end

      private

      def build_session(click_ids:)
        OpenStruct.new(click_ids: click_ids)
      end
    end
  end
end
