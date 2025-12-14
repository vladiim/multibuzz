# frozen_string_literal: true

require "test_helper"
require_relative "../security_test_helper"

module AML
  module Security
    class GlobalVariablesTest < ActiveSupport::TestCase
      include AML::SecurityTestHelper

      test "blocks ENV access" do
        assert_forbidden 'ENV["API_KEY"]'
      end

      test "blocks $LOAD_PATH access" do
        assert_forbidden "$LOAD_PATH"
      end

      test "blocks $LOADED_FEATURES access" do
        assert_forbidden "$LOADED_FEATURES"
      end

      test "blocks $0 access" do
        assert_forbidden "$0"
      end

      test "blocks $PROGRAM_NAME access" do
        assert_forbidden "$PROGRAM_NAME"
      end

      test "blocks $stdin access" do
        assert_forbidden "$stdin"
      end

      test "blocks $stdout access" do
        assert_forbidden "$stdout"
      end

      test "blocks $stderr access" do
        assert_forbidden "$stderr"
      end

      test "blocks $: shorthand" do
        assert_forbidden "$:"
      end

      test "blocks $SAFE access" do
        assert_forbidden "$SAFE"
      end
    end
  end
end
