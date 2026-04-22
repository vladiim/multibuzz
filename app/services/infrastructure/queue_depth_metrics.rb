# frozen_string_literal: true

module Infrastructure
  class QueueDepthMetrics
    def initialize(stuck_duration:, recent_failure_window:)
      @stuck_duration = stuck_duration
      @recent_failure_window = recent_failure_window
    end

    def ready_count = @ready_count ||= SolidQueue::ReadyExecution.count

    def ready_breakdown
      @ready_breakdown ||= SolidQueue::ReadyExecution.joins(:job)
        .group("solid_queue_jobs.class_name").count
    end

    def stuck_count = @stuck_count ||= stuck_scope.count

    def stuck_breakdown
      @stuck_breakdown ||= stuck_scope.group("solid_queue_jobs.class_name").count
    end

    def oldest_stuck_age_minutes
      oldest = stuck_scope.minimum("solid_queue_claimed_executions.created_at")
      return nil unless oldest
      ((Time.current - oldest) / 60).to_i
    end

    def recent_failure_count
      @recent_failure_count ||= SolidQueue::FailedExecution
        .where("created_at > ?", recent_failure_window.ago).count
    end

    private

    attr_reader :stuck_duration, :recent_failure_window

    def stuck_scope
      @stuck_scope ||= SolidQueue::ClaimedExecution.joins(:job)
        .where("solid_queue_claimed_executions.created_at < ?", stuck_duration.ago)
    end
  end
end
