# frozen_string_literal: true

module Infrastructure
  class QueueDepthAlertJob < ApplicationJob
    queue_as :default

    def perform
      QueueDepthAlert.new.call
    end
  end
end
