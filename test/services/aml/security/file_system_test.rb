# frozen_string_literal: true

require "test_helper"
require_relative "../security_test_helper"

module AML
  module Security
    class FileSystemTest < ActiveSupport::TestCase
      include AML::SecurityTestHelper

      test "blocks File.read" do
        assert_forbidden 'File.read("/etc/passwd")'
      end

      test "blocks File.open" do
        assert_forbidden 'File.open("/etc/passwd")'
      end

      test "blocks File.write" do
        assert_forbidden 'File.write("/tmp/evil", "data")'
      end

      test "blocks File.delete" do
        assert_forbidden 'File.delete("/tmp/file")'
      end

      test "blocks Dir.glob" do
        assert_forbidden 'Dir.glob("/*")'
      end

      test "blocks Dir.entries" do
        assert_forbidden 'Dir.entries("/")'
      end

      test "blocks IO.read" do
        assert_forbidden 'IO.read("/etc/passwd")'
      end

      test "blocks IO.readlines" do
        assert_forbidden 'IO.readlines("/etc/passwd")'
      end

      test "blocks FileUtils.rm_rf" do
        assert_forbidden 'FileUtils.rm_rf("/")'
      end

      test "blocks Pathname access" do
        assert_forbidden 'Pathname.new("/etc/passwd").read'
      end
    end
  end
end
