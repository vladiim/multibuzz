# frozen_string_literal: true

module AdPlatforms
  class MetadataBackfillJob < ApplicationJob
    queue_as :default

    def perform(connection_id)
      MetadataBackfillService.new(AdPlatformConnection.find(connection_id)).call
    end
  end
end
