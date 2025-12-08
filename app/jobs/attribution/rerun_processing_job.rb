# frozen_string_literal: true

module Attribution
  class RerunProcessingJob < ApplicationJob
    queue_as :default

    def perform(rerun_job_id)
      RerunService.new(::RerunJob.find(rerun_job_id)).call
    end
  end
end
