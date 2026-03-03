# frozen_string_literal: true

module AdPlatforms
  class SpendSyncSchedulerJob < ApplicationJob
    queue_as :default

    def perform
      AdPlatformConnection.active_connections.find_each do |connection|
        SpendSyncJob.perform_later(connection.id)
      end
    end
  end
end
