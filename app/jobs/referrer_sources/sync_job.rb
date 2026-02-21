# frozen_string_literal: true

module ReferrerSources
  class SyncJob < ApplicationJob
    queue_as :default

    def perform
      SyncService.new.call
    end
  end
end
