# frozen_string_literal: true

module Infrastructure
  class QueueDepthAlert
    DEFAULT_READY_THRESHOLD = 200
    DEFAULT_STUCK_DURATION = 30.minutes
    DEFAULT_RECENT_FAILURE_THRESHOLD = 10
    DEFAULT_RECENT_FAILURE_WINDOW = 1.hour

    # rubocop:disable Metrics/ParameterLists
    def initialize(
      ready_threshold: DEFAULT_READY_THRESHOLD,
      stuck_duration: DEFAULT_STUCK_DURATION,
      recent_failure_threshold: DEFAULT_RECENT_FAILURE_THRESHOLD,
      recent_failure_window: DEFAULT_RECENT_FAILURE_WINDOW,
      metrics: QueueDepthMetrics.new(stuck_duration: stuck_duration, recent_failure_window: recent_failure_window)
    )
      @ready_threshold = ready_threshold
      @stuck_duration = stuck_duration
      @recent_failure_threshold = recent_failure_threshold
      @recent_failure_window = recent_failure_window
      @metrics = metrics
    end
    # rubocop:enable Metrics/ParameterLists

    def call
      report_high_ready_depth! if metrics.ready_count > ready_threshold
      report_stuck_jobs! if metrics.stuck_count.positive?
      report_recent_failures! if metrics.recent_failure_count > recent_failure_threshold
    end

    private

    attr_reader :ready_threshold, :stuck_duration, :recent_failure_threshold, :recent_failure_window, :metrics

    def report_high_ready_depth!
      Rails.error.report(
        RuntimeError.new("Solid Queue ready depth elevated: #{metrics.ready_count} waiting"),
        handled: true,
        context: {
          ready_count: metrics.ready_count,
          breakdown: metrics.ready_breakdown,
          threshold: ready_threshold
        }
      )
    end

    def report_stuck_jobs!
      Rails.error.report(
        RuntimeError.new("Solid Queue stuck jobs: #{metrics.stuck_count} claimed > #{stuck_duration.inspect}"),
        handled: true,
        context: {
          stuck_count: metrics.stuck_count,
          oldest_age_minutes: metrics.oldest_stuck_age_minutes,
          breakdown: metrics.stuck_breakdown,
          threshold_minutes: (stuck_duration / 60).to_i
        }
      )
    end

    def report_recent_failures!
      Rails.error.report(
        RuntimeError.new("Solid Queue recent failures elevated: #{metrics.recent_failure_count} in last #{recent_failure_window.inspect}"),
        handled: true,
        context: {
          recent_failure_count: metrics.recent_failure_count,
          window_minutes: (recent_failure_window / 60).to_i,
          threshold: recent_failure_threshold
        }
      )
    end
  end
end
