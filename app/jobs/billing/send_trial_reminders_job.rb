module Billing
  class SendTrialRemindersJob < ApplicationJob
    queue_as :default

    def perform
      SendTrialRemindersService.new.call
    end
  end
end
