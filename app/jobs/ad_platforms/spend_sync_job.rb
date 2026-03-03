# frozen_string_literal: true

module AdPlatforms
  class SpendSyncJob < ApplicationJob
    queue_as :default

    def perform(connection_id, date_range: nil)
      Google::ConnectionSyncService.new(
        AdPlatformConnection.find(connection_id),
        date_range: date_range
      ).call
    end
  end
end
