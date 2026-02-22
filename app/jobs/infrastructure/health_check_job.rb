# frozen_string_literal: true

module Infrastructure
  class HealthCheckJob < ApplicationJob
    def perform
      log_issues
    end

    private

    def log_issues
      issues.each do |check|
        Rails.logger.warn(
          "[INFRA #{check[:status].to_s.upcase}] #{check[:name]}: #{check[:display]}"
        )
      end
    end

    def issues
      @issues ||= results.reject { |check| check[:status] == :ok }
    end

    def results
      @results ||= Infrastructure::HealthCheckService.new.call
    end
  end
end
