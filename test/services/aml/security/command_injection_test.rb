# frozen_string_literal: true

require "test_helper"
require_relative "../security_test_helper"

module AML
  module Security
    class CommandInjectionTest < ActiveSupport::TestCase
      include AML::SecurityTestHelper

      test "blocks system call" do
        assert_forbidden 'system("ls")'
      end

      test "blocks exec call" do
        assert_forbidden 'exec("ls")'
      end

      test "blocks spawn call" do
        assert_forbidden 'spawn("ls")'
      end

      test "blocks backticks" do
        assert_forbidden "`ls`"
      end

      test "blocks %x command syntax" do
        assert_forbidden "%x{ls}"
      end

      test "blocks Kernel.system" do
        assert_forbidden 'Kernel.system("ls")'
      end

      test "blocks IO.popen" do
        assert_forbidden 'IO.popen("ls")'
      end

      test "blocks Open3.capture2" do
        assert_forbidden 'Open3.capture2("ls")'
      end

      test "blocks PTY.spawn" do
        assert_forbidden 'PTY.spawn("ls")'
      end

      test "blocks Process.spawn" do
        assert_forbidden 'Process.spawn("ls")'
      end

      test "blocks fork" do
        assert_forbidden "fork { }"
      end
    end
  end
end
