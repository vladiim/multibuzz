# frozen_string_literal: true

module DataIntegrity
  class SurveillanceSchedulerJob < ApplicationJob
    queue_as :default

    def perform
      SurveillanceScheduler.new.call
    end
  end
end
