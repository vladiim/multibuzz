module DataIntegrity
  class CleanupJob < ApplicationJob
    queue_as :default

    RETENTION_PERIOD = 30.days

    def perform
      DataIntegrityCheck.where("created_at < ?", RETENTION_PERIOD.ago).delete_all
    end
  end
end
