# frozen_string_literal: true

module DataIntegrity
  class SurveillanceSchedulerJob < ApplicationJob
    queue_as :default

    def perform
      Account.active.find_each do |account|
        SurveillanceJob.perform_later(account.id)
      end
    end
  end
end
