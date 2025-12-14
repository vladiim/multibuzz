# frozen_string_literal: true

require "test_helper"
require_relative "../security_test_helper"

module AML
  module Security
    class ConstantManipulationTest < ActiveSupport::TestCase
      include AML::SecurityTestHelper

      test "blocks Object.const_get" do
        assert_forbidden "Object.const_get(:File)"
      end

      test "blocks Object.const_set" do
        assert_forbidden 'Object.const_set(:EVIL, "value")'
      end

      test "blocks Module.const_get" do
        assert_forbidden "Module.const_get(:Kernel)"
      end

      test "blocks top-level File constant" do
        assert_forbidden '::File.read("/etc/passwd")'
      end

      test "blocks top-level Kernel constant" do
        assert_forbidden '::Kernel.system("ls")'
      end

      test "blocks Object::File" do
        assert_forbidden "Object::File"
      end

      test "blocks class.const_get chain" do
        assert_forbidden '"string".class.const_get(:File)'
      end

      test "blocks class chain to get constants" do
        assert_forbidden "1.class.superclass.const_get(:File)"
      end

      test "blocks accessing File constant" do
        assert_forbidden "File"
      end

      test "blocks accessing Dir constant" do
        assert_forbidden "Dir"
      end

      test "blocks accessing IO constant" do
        assert_forbidden "IO"
      end

      test "blocks accessing Kernel constant" do
        assert_forbidden "Kernel"
      end

      test "blocks accessing Process constant" do
        assert_forbidden "Process"
      end

      test "blocks accessing Net constant" do
        assert_forbidden "Net"
      end

      test "blocks accessing Thread constant" do
        assert_forbidden "Thread"
      end

      test "blocks accessing ObjectSpace constant" do
        assert_forbidden "ObjectSpace"
      end

      test "blocks accessing GC constant" do
        assert_forbidden "GC"
      end
    end
  end
end
