# frozen_string_literal: true

module AdPlatforms
  class SpendSyncJob < ApplicationJob
    queue_as :default

    def perform(connection_id, date_range: nil)
      connection = AdPlatformConnection.find(connection_id)
      Registry.connection_sync_service_for(connection.platform)
        .new(connection, date_range: date_range)
        .call
    end
  end
end
