# frozen_string_literal: true

require "test_helper"
require_relative "../security_test_helper"

module AML
  module Security
    class NetworkAccessTest < ActiveSupport::TestCase
      include AML::SecurityTestHelper

      test "blocks Net::HTTP.get" do
        assert_forbidden 'Net::HTTP.get("evil.com", "/")'
      end

      test "blocks URI.open" do
        assert_forbidden 'URI.open("http://evil.com")'
      end

      test "blocks open with URL" do
        assert_forbidden 'open("http://evil.com")'
      end

      test "blocks require net/http" do
        assert_forbidden 'require "net/http"'
      end

      test "blocks require open-uri" do
        assert_forbidden 'require "open-uri"'
      end

      test "blocks Socket.new" do
        assert_forbidden "Socket.new(:INET, :STREAM)"
      end

      test "blocks TCPSocket" do
        assert_forbidden 'TCPSocket.new("evil.com", 80)'
      end

      test "blocks UDPSocket" do
        assert_forbidden "UDPSocket.new"
      end

      test "blocks HTTP constant" do
        assert_forbidden "HTTP"
      end

      test "blocks URI constant" do
        assert_forbidden "URI"
      end
    end
  end
end
