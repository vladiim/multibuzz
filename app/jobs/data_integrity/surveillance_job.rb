# frozen_string_literal: true

module DataIntegrity
  class SurveillanceJob < ApplicationJob
    queue_as :default

    def perform(account_id)
      DataIntegrity::CheckRunner.new(Account.find(account_id)).call
    end
  end
end
