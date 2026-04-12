# frozen_string_literal: true

module DataIntegrity
  class SurveillanceScheduler
    def call
      Account.active.find_each do |account|
        next if job_already_queued?(account.id)

        SurveillanceJob.perform_later(account.id)
      end
    end

    private

    def job_already_queued?(account_id)
      SolidQueue::Job
        .where(class_name: "DataIntegrity::SurveillanceJob", finished_at: nil)
        .where("arguments LIKE ?", "%[#{account_id}]%")
        .exists?
    rescue ActiveRecord::StatementInvalid
      false
    end
  end
end
