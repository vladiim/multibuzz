# frozen_string_literal: true

module Infrastructure
  class HealthCheckService
    CHECK_CLASSES = [
      Checks::DatabaseSize,
      Checks::ConnectionUsage,
      Checks::QueueDepth,
      Checks::CompressionRatio,
      Checks::LongRunningQueries
    ].freeze

    def call
      CHECK_CLASSES.map { |klass| klass.new.call }
    end

    def critical?
      call.any? { |check| check[:status] == :critical }
    end
  end
end
