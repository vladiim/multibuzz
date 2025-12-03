# frozen_string_literal: true

module Billing
  class ExpireFreeUntilJob < ApplicationJob
    queue_as :default

    def perform
      ExpireFreeUntilService.new.call
    end
  end
end
