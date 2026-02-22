# frozen_string_literal: true

require "test_helper"

module Infrastructure
  class HealthCheckServiceTest < ActiveSupport::TestCase
    test "returns results for all checks" do
      assert_equal Infrastructure::HealthCheckService::CHECK_CLASSES.size, results.size
    end

    test "each result has required keys" do
      results.each do |result|
        assert result.key?(:name), "Missing :name in #{result}"
        assert result.key?(:value), "Missing :value in #{result}"
        assert result.key?(:status), "Missing :status in #{result}"
      end
    end

    test "each result has a valid status" do
      valid_statuses = %i[ok warning critical error]

      results.each do |result|
        assert_includes valid_statuses, result[:status],
          "Invalid status #{result[:status]} for #{result[:name]}"
      end
    end

    test "critical? returns false when all checks pass" do
      assert_not service.critical?
    end

    private

    def service = @service ||= Infrastructure::HealthCheckService.new
    def results = @results ||= service.call
  end
end
