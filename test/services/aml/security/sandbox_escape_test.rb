# frozen_string_literal: true

require "test_helper"
require_relative "../security_test_helper"

module AML
  module Security
    class SandboxEscapeTest < ActiveSupport::TestCase
      include AML::SecurityTestHelper

      test "blocks class method to access constants" do
        assert_forbidden '"string".class.const_get(:File)'
      end

      test "blocks class chain escape" do
        assert_forbidden "1.class.superclass.const_get(:File)"
      end

      test "blocks singleton_class access" do
        assert_forbidden "singleton_class"
      end

      test "blocks object_id access" do
        assert_forbidden "object_id"
      end

      test "blocks __id__ access" do
        assert_forbidden "__id__"
      end

      test "blocks __method__ access" do
        assert_forbidden "__method__"
      end

      test "blocks __callee__ access" do
        assert_forbidden "__callee__"
      end

      test "blocks ObjectSpace.each_object" do
        assert_forbidden "ObjectSpace.each_object(String) { |s| puts s }"
      end

      test "blocks GC.start" do
        assert_forbidden "GC.start"
      end

      test "blocks Thread.new" do
        assert_forbidden "Thread.new { }"
      end

      test "blocks Fiber.new" do
        assert_forbidden "Fiber.new { }"
      end

      test "blocks Proc binding access" do
        assert_forbidden "Proc.new { }.binding"
      end

      test "blocks lambda binding access" do
        assert_forbidden "lambda { }.binding"
      end

      test "blocks extend" do
        assert_forbidden "extend(SomeModule)"
      end

      test "blocks include" do
        assert_forbidden "include(SomeModule)"
      end

      test "blocks prepend" do
        assert_forbidden "prepend(SomeModule)"
      end

      test "blocks class access" do
        assert_forbidden '"string".class'
      end

      test "blocks instance_variable_get" do
        assert_forbidden "instance_variable_get(:@secret)"
      end

      test "blocks instance_variable_set" do
        assert_forbidden 'instance_variable_set(:@secret, "value")'
      end

      test "blocks class_variable_get" do
        assert_forbidden "class_variable_get(:@@secret)"
      end

      test "blocks class_variable_set" do
        assert_forbidden 'class_variable_set(:@@secret, "value")'
      end
    end
  end
end
