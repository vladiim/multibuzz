# frozen_string_literal: true

module Infrastructure
  class QueueCleanup
    STALE_THRESHOLD = 24.hours
    ALERT_THRESHOLD = 50

    def call
      count = stale_scope.count
      return if count.zero?

      alert_stuck_jobs(count, stale_scope.group(:class_name).count) if count > ALERT_THRESHOLD
      stale_scope.destroy_all
      Rails.logger.info("[QueueCleanup] Purged #{count} stuck jobs")
    end

    private

    def stale_scope
      SolidQueue::Job.where(finished_at: nil).where("created_at < ?", STALE_THRESHOLD.ago)
    end

    def alert_stuck_jobs(count, breakdown)
      Rails.error.report(
        RuntimeError.new("#{count} stuck jobs detected, purging"),
        handled: true,
        context: { stuck_count: count, breakdown: breakdown }
      )
    end
  end
end
