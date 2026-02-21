# frozen_string_literal: true

require "test_helper"

module DataIntegrity
  class CheckRunnerTest < ActiveSupport::TestCase
    test "runs all checks and persists results" do
      result = build_runner(3.times.map { |i|
        mock_check_class(check_name: "test_check_#{i}", value: i * 10.0, status: :healthy)
      }).call

      assert result[:success]
      assert_equal 3, result[:results].size
      assert_equal 3, account.data_integrity_checks.where("created_at > ?", 1.minute.ago).count
    end

    test "persists check attributes correctly" do
      build_runner([
        mock_check_class(
          check_name: "ghost_session_rate",
          value: 35.0,
          status: :warning,
          warning_threshold: 20.0,
          critical_threshold: 50.0,
          details: { total: 100, ghost: 35 }
        )
      ]).call

      check = account.data_integrity_checks.order(created_at: :desc).first

      assert_equal "ghost_session_rate", check.check_name
      assert_equal "warning", check.status
      assert_in_delta 35.0, check.value
      assert_in_delta 20.0, check.warning_threshold
      assert_in_delta 50.0, check.critical_threshold
      assert_equal({ "total" => 100, "ghost" => 35 }, check.details)
    end

    test "returns error on persistence failure" do
      result = build_runner([
        mock_check_class(check_name: nil, value: 5.0, status: :healthy)
      ]).call

      assert_not result[:success]
      assert result[:errors].any? { |e| e.include?("Record invalid") }
    end

    private

    def account
      @account ||= accounts(:one)
    end

    def build_runner(check_classes)
      runner = CheckRunner.new(account)
      runner.define_singleton_method(:check_classes) { check_classes }
      runner
    end

    def mock_check_class(check_name:, value:, status:, warning_threshold: 20.0, critical_threshold: 50.0, details: {})
      result = {
        check_name: check_name,
        value: value,
        status: status,
        warning_threshold: warning_threshold,
        critical_threshold: critical_threshold,
        details: details
      }

      Class.new do
        define_method(:initialize) { |_account| }
        define_method(:call) { result }
      end
    end
  end
end
