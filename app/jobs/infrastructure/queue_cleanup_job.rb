# frozen_string_literal: true

module Infrastructure
  class QueueCleanupJob < ApplicationJob
    queue_as :default

    def perform
      QueueCleanup.new.call
    end
  end
end
