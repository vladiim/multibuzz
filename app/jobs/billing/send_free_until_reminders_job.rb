module Billing
  class SendFreeUntilRemindersJob < ApplicationJob
    queue_as :default

    def perform
      SendFreeUntilRemindersService.new.call
    end
  end
end
