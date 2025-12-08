# frozen_string_literal: true

require "test_helper"
require_relative "../security_test_helper"

module AML
  module Security
    class EvalMetaprogrammingTest < ActiveSupport::TestCase
      include AML::SecurityTestHelper

      test "blocks eval" do
        assert_forbidden 'eval("malicious_code")'
      end

      test "blocks instance_eval with string" do
        assert_forbidden 'instance_eval("malicious_code")'
      end

      test "blocks instance_eval with block" do
        assert_forbidden "instance_eval { system('ls') }"
      end

      test "blocks class_eval" do
        assert_forbidden 'class_eval("malicious_code")'
      end

      test "blocks module_eval" do
        assert_forbidden 'module_eval("malicious_code")'
      end

      test "blocks send" do
        assert_forbidden 'send(:system, "ls")'
      end

      test "blocks __send__" do
        assert_forbidden '__send__(:system, "ls")'
      end

      test "blocks public_send" do
        assert_forbidden 'public_send(:system, "ls")'
      end

      test "blocks define_method" do
        assert_forbidden 'define_method(:evil) { system("ls") }'
      end

      test "blocks define_singleton_method" do
        assert_forbidden 'define_singleton_method(:evil) { }'
      end

      test "blocks undef_method" do
        assert_forbidden "undef_method(:to_s)"
      end

      test "blocks remove_method" do
        assert_forbidden "remove_method(:to_s)"
      end

      test "blocks method call" do
        assert_forbidden 'method(:system).call("ls")'
      end

      test "blocks binding access" do
        assert_forbidden "binding"
      end

      test "blocks caller access" do
        assert_forbidden "caller"
      end

      test "blocks caller_locations access" do
        assert_forbidden "caller_locations"
      end
    end
  end
end
